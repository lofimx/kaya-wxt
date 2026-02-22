use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use chrono::Utc;
use clap::Parser;
use rand::RngCore;
use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_256_GCM};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use thiserror::Error;
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

use savebutton_daemon::parse_server_file_listing;

const DEFAULT_PORT: u16 = 21420;
const NONCE_LEN: usize = 12;
const KEY_LEN: usize = 32;

#[derive(Parser)]
#[command(name = "savebutton-daemon")]
#[command(about = "Optional local daemon for the Save Button browser extension")]
struct Cli {
    /// Port to listen on
    #[arg(long, default_value_t = DEFAULT_PORT)]
    port: u16,
}

fn setup_logging() {
    let log_path = get_kaya_dir().join("daemon-log");

    let base = fern::Dispatch::new()
        .format(|out, message, record| {
            out.finish(format_args!(
                "[{}] {}: {}",
                Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ"),
                record.level(),
                message
            ))
        })
        .level(log::LevelFilter::Info)
        .chain(io::stderr());

    let dispatch = if let Ok(log_file) = fern::log_file(&log_path) {
        base.chain(log_file)
    } else {
        eprintln!(
            "Warning: could not open log file {:?}, logging to stderr only",
            log_path
        );
        base
    };

    if let Err(e) = dispatch.apply() {
        eprintln!("Warning: failed to initialize logging: {}", e);
    }
}

#[derive(Error, Debug)]
enum KayaError {
    #[error("IO error: {0}")]
    Io(#[from] io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("Base64 decode error: {0}")]
    Base64(#[from] base64::DecodeError),
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("Config error: {0}")]
    Config(String),
    #[error("Encryption error: {0}")]
    Encryption(String),
}

#[derive(Debug, Serialize, Deserialize, Default)]
struct Config {
    server: Option<String>,
    email: Option<String>,
    encrypted_password: Option<String>,
    encryption_key: Option<String>,
}

fn get_kaya_dir() -> PathBuf {
    dirs::home_dir()
        .expect("Could not find home directory")
        .join(".kaya")
}

fn get_anga_dir() -> PathBuf {
    get_kaya_dir().join("anga")
}

fn get_meta_dir() -> PathBuf {
    get_kaya_dir().join("meta")
}

fn get_words_dir() -> PathBuf {
    get_kaya_dir().join("words")
}

fn get_config_path() -> PathBuf {
    get_kaya_dir().join(".config")
}

fn ensure_directories() -> io::Result<()> {
    fs::create_dir_all(get_anga_dir())?;
    fs::create_dir_all(get_meta_dir())?;
    fs::create_dir_all(get_words_dir())?;
    Ok(())
}

fn generate_encryption_key() -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];
    rand::thread_rng().fill_bytes(&mut key);
    key
}

fn encrypt_password(password: &str, key: &[u8; KEY_LEN]) -> Result<String, KayaError> {
    let unbound_key = UnboundKey::new(&AES_256_GCM, key)
        .map_err(|e| KayaError::Encryption(format!("Failed to create key: {:?}", e)))?;
    let key = LessSafeKey::new(unbound_key);

    let mut nonce_bytes = [0u8; NONCE_LEN];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::assume_unique_for_key(nonce_bytes);

    let mut in_out = password.as_bytes().to_vec();
    key.seal_in_place_append_tag(nonce, Aad::empty(), &mut in_out)
        .map_err(|e| KayaError::Encryption(format!("Failed to encrypt: {:?}", e)))?;

    let mut result = nonce_bytes.to_vec();
    result.extend(in_out);
    Ok(BASE64.encode(&result))
}

fn decrypt_password(encrypted: &str, key: &[u8; KEY_LEN]) -> Result<String, KayaError> {
    let data = BASE64.decode(encrypted)?;
    if data.len() < NONCE_LEN + 16 {
        return Err(KayaError::Encryption("Invalid encrypted data".to_string()));
    }

    let (nonce_bytes, ciphertext) = data.split_at(NONCE_LEN);
    let nonce_array: [u8; NONCE_LEN] = nonce_bytes
        .try_into()
        .map_err(|_| KayaError::Encryption("Invalid nonce".to_string()))?;
    let nonce = Nonce::assume_unique_for_key(nonce_array);

    let unbound_key = UnboundKey::new(&AES_256_GCM, key)
        .map_err(|e| KayaError::Encryption(format!("Failed to create key: {:?}", e)))?;
    let key = LessSafeKey::new(unbound_key);

    let mut in_out = ciphertext.to_vec();
    let plaintext = key
        .open_in_place(nonce, Aad::empty(), &mut in_out)
        .map_err(|e| KayaError::Encryption(format!("Failed to decrypt: {:?}", e)))?;

    String::from_utf8(plaintext.to_vec())
        .map_err(|e| KayaError::Encryption(format!("Invalid UTF-8: {}", e)))
}

fn load_config() -> Result<Config, KayaError> {
    let path = get_config_path();
    if !path.exists() {
        return Ok(Config::default());
    }
    let content = fs::read_to_string(&path)?;
    let config: Config = toml::from_str(&content)
        .map_err(|e| KayaError::Config(format!("Invalid config: {}", e)))?;
    Ok(config)
}

fn save_config(config: &Config) -> Result<(), KayaError> {
    ensure_directories()?;
    let content = toml::to_string(config)
        .map_err(|e| KayaError::Config(format!("Failed to serialize: {}", e)))?;
    fs::write(get_config_path(), content)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Server sync logic
// ---------------------------------------------------------------------------

fn sync_with_server() -> Result<(), KayaError> {
    let config = load_config()?;

    let server = match config.server {
        Some(s) => s,
        None => return Ok(()),
    };

    let email = match config.email {
        Some(e) => e,
        None => return Ok(()),
    };

    let password = match (&config.encrypted_password, &config.encryption_key) {
        (Some(enc), Some(key_b64)) => {
            let key_bytes = BASE64.decode(key_b64)?;
            let key: [u8; KEY_LEN] = key_bytes
                .try_into()
                .map_err(|_| KayaError::Encryption("Invalid key length".to_string()))?;
            decrypt_password(enc, &key)?
        }
        _ => return Ok(()),
    };

    let client = reqwest::blocking::Client::new();

    let (anga_downloaded, anga_uploaded) =
        sync_collection(&client, &server, &email, &password, "anga")?;
    let (meta_downloaded, meta_uploaded) =
        sync_collection(&client, &server, &email, &password, "meta")?;
    let words_downloaded = sync_words(&client, &server, &email, &password)?;

    let total_downloaded = anga_downloaded + meta_downloaded + words_downloaded;
    let total_uploaded = anga_uploaded + meta_uploaded;

    if total_downloaded > 0 || total_uploaded > 0 {
        log::info!(
            "Sync complete: {} downloaded, {} uploaded",
            total_downloaded,
            total_uploaded
        );
    }

    Ok(())
}

fn sync_collection(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
    collection: &str,
) -> Result<(usize, usize), KayaError> {
    let url = format!(
        "{}/api/v1/{}/{}",
        server.trim_end_matches('/'),
        urlencoding::encode(email),
        collection
    );

    let response = client.get(&url).basic_auth(email, Some(password)).send()?;

    if !response.status().is_success() {
        return Err(KayaError::Http(response.error_for_status().unwrap_err()));
    }

    let server_files: HashSet<String> = parse_server_file_listing(&response.text()?);

    let local_dir = if collection == "anga" {
        get_anga_dir()
    } else {
        get_meta_dir()
    };

    let local_files: HashSet<String> = if local_dir.exists() {
        fs::read_dir(&local_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_file())
            .filter_map(|e| e.file_name().into_string().ok())
            .filter(|n| !n.starts_with('.') && (collection == "anga" || n.ends_with(".toml")))
            .collect()
    } else {
        HashSet::new()
    };

    let to_download: Vec<_> = server_files.difference(&local_files).collect();
    let to_upload: Vec<_> = local_files.difference(&server_files).collect();

    let downloaded = to_download.len();
    let uploaded = to_upload.len();

    for filename in to_download {
        log::info!("  downloading {}: {}", collection, filename);
        download_file(client, server, email, password, collection, filename)?;
    }

    for filename in to_upload {
        log::info!("  uploading {}: {}", collection, filename);
        upload_file(client, server, email, password, collection, filename)?;
    }

    Ok((downloaded, uploaded))
}

fn download_file(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
    collection: &str,
    filename: &str,
) -> Result<(), KayaError> {
    let url = format!(
        "{}/api/v1/{}/{}/{}",
        server.trim_end_matches('/'),
        urlencoding::encode(email),
        collection,
        filename
    );

    let response = client.get(&url).basic_auth(email, Some(password)).send()?;

    if response.status().is_success() {
        let content = response.bytes()?;
        let dir = if collection == "anga" {
            get_anga_dir()
        } else {
            get_meta_dir()
        };
        fs::write(dir.join(filename), content)?;
    }

    Ok(())
}

fn upload_file(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
    collection: &str,
    filename: &str,
) -> Result<(), KayaError> {
    let dir = if collection == "anga" {
        get_anga_dir()
    } else {
        get_meta_dir()
    };
    let path = dir.join(filename);
    let content = fs::read(&path)?;

    let url = format!(
        "{}/api/v1/{}/{}/{}",
        server.trim_end_matches('/'),
        urlencoding::encode(email),
        collection,
        urlencoding::encode(filename)
    );

    let content_type = mime_type_for(filename);

    let part = reqwest::blocking::multipart::Part::bytes(content)
        .file_name(filename.to_string())
        .mime_str(&content_type)
        .unwrap();

    let form = reqwest::blocking::multipart::Form::new().part("file", part);

    let response = client
        .post(&url)
        .basic_auth(email, Some(password))
        .multipart(form)
        .send()?;

    if response.status() == reqwest::StatusCode::CONFLICT {
        // File already exists, that's fine
    } else if !response.status().is_success() {
        log::error!(
            "Failed to upload {} {}: {}",
            collection,
            filename,
            response.status()
        );
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Words sync (download-only from server, nested: words/{anga}/{filename})
// ---------------------------------------------------------------------------

fn sync_words(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
) -> Result<usize, KayaError> {
    let url = format!(
        "{}/api/v1/{}/words",
        server.trim_end_matches('/'),
        urlencoding::encode(email),
    );

    let response = client.get(&url).basic_auth(email, Some(password)).send()?;

    if !response.status().is_success() {
        return Err(KayaError::Http(response.error_for_status().unwrap_err()));
    }

    let anga_dirs: HashSet<String> = parse_server_file_listing(&response.text()?);
    let mut downloaded = 0;

    for anga in &anga_dirs {
        let anga_url = format!(
            "{}/api/v1/{}/words/{}",
            server.trim_end_matches('/'),
            urlencoding::encode(email),
            urlencoding::encode(anga),
        );

        let response = client
            .get(&anga_url)
            .basic_auth(email, Some(password))
            .send()?;

        if !response.status().is_success() {
            continue;
        }

        let server_files: HashSet<String> = parse_server_file_listing(&response.text()?);

        let local_anga_dir = get_words_dir().join(anga);
        let local_files: HashSet<String> = if local_anga_dir.exists() {
            fs::read_dir(&local_anga_dir)?
                .filter_map(|e| e.ok())
                .filter(|e| e.path().is_file())
                .filter_map(|e| e.file_name().into_string().ok())
                .collect()
        } else {
            HashSet::new()
        };

        for filename in server_files.difference(&local_files) {
            let file_url = format!(
                "{}/api/v1/{}/words/{}/{}",
                server.trim_end_matches('/'),
                urlencoding::encode(email),
                urlencoding::encode(anga),
                urlencoding::encode(filename),
            );

            let response = client
                .get(&file_url)
                .basic_auth(email, Some(password))
                .send()?;

            if response.status().is_success() {
                let content = response.bytes()?;
                fs::create_dir_all(&local_anga_dir)?;
                fs::write(local_anga_dir.join(filename), content)?;
                log::info!("  downloading words/{}/{}", anga, filename);
                downloaded += 1;
            }
        }
    }

    Ok(downloaded)
}

fn mime_type_for(filename: &str) -> String {
    let ext = filename.rsplit('.').next().unwrap_or("").to_lowercase();
    match ext.as_str() {
        "md" => "text/markdown",
        "url" | "txt" => "text/plain",
        "json" => "application/json",
        "toml" => "application/toml",
        "pdf" => "application/pdf",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "html" | "htm" => "text/html",
        _ => "application/octet-stream",
    }
    .to_string()
}

// ---------------------------------------------------------------------------
// HTTP server handlers
// ---------------------------------------------------------------------------

fn cors_headers() -> Vec<Header> {
    vec![
        Header::from_bytes("Access-Control-Allow-Origin", "*").unwrap(),
        Header::from_bytes("Access-Control-Allow-Methods", "GET, POST, OPTIONS").unwrap(),
        Header::from_bytes("Access-Control-Allow-Headers", "Content-Type").unwrap(),
    ]
}

fn respond_ok(request: Request, body: &str) {
    let mut response = Response::from_string(body).with_status_code(StatusCode(200));
    for h in cors_headers() {
        response.add_header(h);
    }
    let _ = request.respond(response);
}

fn respond_error(request: Request, status: u16, msg: &str) {
    let mut response = Response::from_string(msg).with_status_code(StatusCode(status));
    for h in cors_headers() {
        response.add_header(h);
    }
    let _ = request.respond(response);
}

fn respond_no_content(request: Request) {
    let mut response = Response::from_string("").with_status_code(StatusCode(204));
    for h in cors_headers() {
        response.add_header(h);
    }
    let _ = request.respond(response);
}

fn handle_request(request: Request) {
    let method = request.method().clone();
    let url = request.url().to_string();

    // Handle CORS preflight
    if method == Method::Options {
        respond_no_content(request);
        return;
    }

    // Route: GET /health
    if method == Method::Get && url == "/health" {
        respond_ok(request, "ok");
        return;
    }

    // Route: GET /anga -- list anga files
    if method == Method::Get && url == "/anga" {
        match list_files("anga") {
            Ok(listing) => respond_ok(request, &listing),
            Err(e) => respond_error(request, 500, &e.to_string()),
        }
        return;
    }

    // Route: GET /meta -- list meta files
    if method == Method::Get && url == "/meta" {
        match list_files("meta") {
            Ok(listing) => respond_ok(request, &listing),
            Err(e) => respond_error(request, 500, &e.to_string()),
        }
        return;
    }

    // Route: POST /anga/{filename} -- write anga file
    if method == Method::Post && url.starts_with("/anga/") {
        let filename = urlencoding::decode(&url[6..])
            .unwrap_or_default()
            .into_owned();
        if filename.is_empty() || filename.contains('/') || filename.contains("..") {
            respond_error(request, 400, "Invalid filename");
            return;
        }
        match write_uploaded_file(request, "anga", &filename) {
            Ok(()) => {}
            Err(e) => log::error!("Failed to write anga {}: {}", filename, e),
        }
        return;
    }

    // Route: POST /meta/{filename} -- write meta file
    if method == Method::Post && url.starts_with("/meta/") {
        let filename = urlencoding::decode(&url[6..])
            .unwrap_or_default()
            .into_owned();
        if filename.is_empty() || filename.contains('/') || filename.contains("..") {
            respond_error(request, 400, "Invalid filename");
            return;
        }
        match write_uploaded_file(request, "meta", &filename) {
            Ok(()) => {}
            Err(e) => log::error!("Failed to write meta {}: {}", filename, e),
        }
        return;
    }

    // Route: GET /words -- list anga subdirectories under ~/.kaya/words/
    if method == Method::Get && url == "/words" {
        match list_words_dirs() {
            Ok(listing) => respond_ok(request, &listing),
            Err(e) => respond_error(request, 500, &e.to_string()),
        }
        return;
    }

    // Route: GET /words/{anga} -- list files in a words anga subdir
    if method == Method::Get && url.starts_with("/words/") && url.matches('/').count() == 2 {
        let anga = urlencoding::decode(&url[7..])
            .unwrap_or_default()
            .into_owned();
        if anga.is_empty() || anga.contains('/') || anga.contains("..") {
            respond_error(request, 400, "Invalid anga name");
            return;
        }
        match list_words_files(&anga) {
            Ok(listing) => respond_ok(request, &listing),
            Err(e) => respond_error(request, 500, &e.to_string()),
        }
        return;
    }

    // Route: POST /words/{anga}/{filename} -- write a words file
    if method == Method::Post && url.starts_with("/words/") && url.matches('/').count() == 3 {
        let path = &url[7..]; // strip "/words/"
        if let Some((anga, filename)) = path.split_once('/') {
            let anga = urlencoding::decode(anga).unwrap_or_default().into_owned();
            let filename = urlencoding::decode(filename)
                .unwrap_or_default()
                .into_owned();
            if anga.is_empty()
                || anga.contains("..")
                || filename.is_empty()
                || filename.contains('/')
                || filename.contains("..")
            {
                respond_error(request, 400, "Invalid path");
                return;
            }
            match write_words_file(request, &anga, &filename) {
                Ok(()) => {}
                Err(e) => log::error!("Failed to write words/{}/{}: {}", anga, filename, e),
            }
            return;
        }
        respond_error(request, 400, "Invalid path");
        return;
    }

    // Route: POST /config -- receive config from extension
    if method == Method::Post && url == "/config" {
        match handle_config_post(request) {
            Ok(()) => {}
            Err(e) => log::error!("Failed to save config: {}", e),
        }
        return;
    }

    respond_error(request, 404, "Not found");
}

#[derive(Deserialize)]
struct IncomingConfig {
    server: String,
    email: String,
    password: String,
}

fn handle_config_post(mut request: Request) -> Result<(), KayaError> {
    let mut body = String::new();
    request
        .as_reader()
        .read_to_string(&mut body)
        .map_err(KayaError::Io)?;

    let incoming: IncomingConfig = serde_json::from_str(&body)?;

    let key = generate_encryption_key();
    let encrypted = encrypt_password(&incoming.password, &key)?;

    let config = Config {
        server: Some(incoming.server),
        email: Some(incoming.email),
        encrypted_password: Some(encrypted),
        encryption_key: Some(BASE64.encode(key)),
    };

    save_config(&config)?;
    log::info!("Config updated via POST /config");

    respond_ok(request, r#"{"ok":true}"#);
    Ok(())
}

fn list_words_dirs() -> Result<String, KayaError> {
    let dir = get_words_dir();
    if !dir.exists() {
        return Ok(String::new());
    }

    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| !n.starts_with('.'))
        .collect();

    names.sort();
    Ok(names.join("\n"))
}

fn list_words_files(anga: &str) -> Result<String, KayaError> {
    let dir = get_words_dir().join(anga);
    if !dir.exists() {
        return Ok(String::new());
    }

    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_file())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();

    names.sort();
    Ok(names.join("\n"))
}

fn write_words_file(mut request: Request, anga: &str, filename: &str) -> Result<(), KayaError> {
    let mut body = Vec::new();
    request
        .as_reader()
        .read_to_end(&mut body)
        .map_err(KayaError::Io)?;

    let dir = get_words_dir().join(anga);
    fs::create_dir_all(&dir)?;
    fs::write(dir.join(filename), &body)?;
    log::info!("Wrote words/{}/{}", anga, filename);

    respond_ok(request, "ok");
    Ok(())
}

fn list_files(collection: &str) -> Result<String, KayaError> {
    let dir = if collection == "anga" {
        get_anga_dir()
    } else {
        get_meta_dir()
    };

    if !dir.exists() {
        return Ok(String::new());
    }

    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_file())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| !n.starts_with('.'))
        .collect();

    names.sort();
    Ok(names.join("\n"))
}

fn write_uploaded_file(
    mut request: Request,
    collection: &str,
    filename: &str,
) -> Result<(), KayaError> {
    let mut body = Vec::new();
    request
        .as_reader()
        .read_to_end(&mut body)
        .map_err(KayaError::Io)?;

    let dir = if collection == "anga" {
        get_anga_dir()
    } else {
        get_meta_dir()
    };

    ensure_directories()?;
    fs::write(dir.join(filename), &body)?;
    log::info!("Wrote {} {}", collection, filename);

    respond_ok(request, "ok");
    Ok(())
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() {
    let cli = Cli::parse();

    setup_logging();

    if let Err(e) = ensure_directories() {
        log::error!("Failed to create directories: {}", e);
        std::process::exit(1);
    }

    let addr = format!("127.0.0.1:{}", cli.port);
    let server = match Server::http(&addr) {
        Ok(s) => s,
        Err(e) => {
            log::error!("Failed to start HTTP server on {}: {}", addr, e);
            eprintln!("Failed to start HTTP server on {}: {}", addr, e);
            std::process::exit(1);
        }
    };

    log::info!("Save Button daemon listening on {}", addr);
    println!("Save Button daemon listening on {}", addr);

    let running = Arc::new(AtomicBool::new(true));
    let running_clone = running.clone();

    // Background sync thread: sync every 60 seconds
    thread::spawn(move || {
        while running_clone.load(Ordering::Relaxed) {
            if let Err(e) = sync_with_server() {
                log::error!("Sync error: {}", e);
            }
            thread::sleep(Duration::from_secs(60));
        }
    });

    for request in server.incoming_requests() {
        handle_request(request);
    }
}
