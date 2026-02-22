use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use chrono::Utc;
use clap::Parser;
use native_messaging::host::{self, NmError};
use native_messaging::{install, remove, Scope};
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

mod extra_browsers;

use savebutton_nativehost::parse_server_file_listing;

const NATIVE_HOST_NAME: &str = "org.savebutton.nativehost";
const NATIVE_HOST_DESCRIPTION: &str = "Save Button native messaging host";
const FIREFOX_EXTENSION_ID: &str = "org.savebutton@savebutton.org";
// Stable dev ID derived from the static key in wxt.config.ts.
// TODO: update after Chrome Web Store publish if the store assigns a different ID.
const CHROME_EXTENSION_ORIGIN: &str = "chrome-extension://kpdhgjmpibjlajlhagbgmnpjifbdbjhd/";

const ALL_BROWSERS: &[&str] = &[
    "chrome",
    "edge",
    "chromium",
    "brave",
    "vivaldi",
    "firefox",
    "librewolf",
];

const NONCE_LEN: usize = 12;
const KEY_LEN: usize = 32;

#[derive(Parser)]
#[command(name = "savebutton-nativehost")]
#[command(about = "Native messaging host for the Save Button browser extension")]
struct Cli {
    /// Install native messaging manifests for all detected browsers
    #[arg(long)]
    install: bool,

    /// Remove native messaging manifests for all browsers
    #[arg(long)]
    uninstall: bool,
}

fn setup_logging() {
    let log_path = get_kaya_dir().join("log");

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
    #[error("Native messaging error: {0}")]
    NativeMessaging(String),
}

impl From<NmError> for KayaError {
    fn from(e: NmError) -> Self {
        KayaError::NativeMessaging(e.to_string())
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct IncomingMessage {
    id: Option<u64>,
    message: String,
    filename: Option<String>,
    #[serde(rename = "type")]
    content_type: Option<String>,
    text: Option<String>,
    base64: Option<String>,
    server: Option<String>,
    email: Option<String>,
    password: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct OutgoingMessage {
    id: Option<u64>,
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    urls: Option<Vec<String>>,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    message_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    has_password: Option<bool>,
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

fn get_config_path() -> PathBuf {
    get_kaya_dir().join(".config")
}

fn ensure_directories() -> io::Result<()> {
    fs::create_dir_all(get_anga_dir())?;
    fs::create_dir_all(get_meta_dir())?;
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

fn handle_config_status(_msg: &IncomingMessage) -> Result<bool, KayaError> {
    let config = load_config()?;
    let has_password = config.encrypted_password.is_some();
    Ok(has_password)
}

fn handle_test_connection(msg: &IncomingMessage) -> Result<(), KayaError> {
    let config = load_config()?;

    let server = msg
        .server
        .as_ref()
        .or(config.server.as_ref())
        .ok_or_else(|| KayaError::Config("Missing server".to_string()))?
        .clone();
    let email = msg
        .email
        .as_ref()
        .or(config.email.as_ref())
        .ok_or_else(|| KayaError::Config("Missing email".to_string()))?
        .clone();

    let password = if let Some(pwd) = msg.password.as_ref() {
        pwd.clone()
    } else {
        match (&config.encrypted_password, &config.encryption_key) {
            (Some(enc), Some(key_b64)) => {
                let key_bytes = BASE64.decode(key_b64)?;
                let key: [u8; KEY_LEN] = key_bytes
                    .try_into()
                    .map_err(|_| KayaError::Encryption("Invalid key length".to_string()))?;
                decrypt_password(enc, &key)?
            }
            _ => return Err(KayaError::Config("No password configured".to_string())),
        }
    };

    let url = format!(
        "{}/api/v1/{}/anga",
        server.trim_end_matches('/'),
        urlencoding::encode(&email)
    );

    log::info!("Testing connection to {}", url);

    let client = reqwest::blocking::Client::new();
    let response = client
        .get(&url)
        .basic_auth(&email, Some(&password))
        .send()?;

    if response.status().is_success() {
        log::info!("Connection test successful");
        Ok(())
    } else if response.status() == reqwest::StatusCode::UNAUTHORIZED {
        Err(KayaError::Config(
            "Authentication failed - check your email and password".to_string(),
        ))
    } else {
        Err(KayaError::Config(format!(
            "Server returned status {}",
            response.status()
        )))
    }
}

fn handle_config_message(msg: &IncomingMessage) -> Result<(), KayaError> {
    log::info!(
        "Received config message: server={:?}, email={:?}",
        msg.server,
        msg.email
    );

    let existing = load_config().unwrap_or_default();

    let server = msg.server.clone().or(existing.server);
    let email = msg.email.clone().or(existing.email);

    let (encrypted_password, encryption_key) = if let Some(ref pwd) = msg.password {
        let key = generate_encryption_key();
        let enc = encrypt_password(pwd, &key)?;
        (Some(enc), Some(BASE64.encode(key)))
    } else {
        (existing.encrypted_password, existing.encryption_key)
    };

    let config = Config {
        server,
        email,
        encrypted_password,
        encryption_key,
    };

    save_config(&config)?;
    Ok(())
}

fn handle_anga_message(msg: &IncomingMessage) -> Result<(), KayaError> {
    log::info!(
        "Received anga message: filename={:?}, type={:?}",
        msg.filename,
        msg.content_type
    );

    ensure_directories()?;

    let filename = msg
        .filename
        .as_ref()
        .ok_or_else(|| KayaError::Config("Missing filename".to_string()))?;

    let content = match msg.content_type.as_deref() {
        Some("base64") => {
            let b64 = msg
                .base64
                .as_ref()
                .ok_or_else(|| KayaError::Config("Missing base64 content".to_string()))?;
            BASE64.decode(b64)?
        }
        Some("text") | None => {
            let text = msg
                .text
                .as_ref()
                .ok_or_else(|| KayaError::Config("Missing text content".to_string()))?;
            text.as_bytes().to_vec()
        }
        Some(t) => return Err(KayaError::Config(format!("Unknown content type: {}", t))),
    };

    let path = get_anga_dir().join(filename);
    fs::write(&path, content)?;

    Ok(())
}

fn handle_meta_message(msg: &IncomingMessage) -> Result<(), KayaError> {
    log::info!("Received meta message: filename={:?}", msg.filename);

    ensure_directories()?;

    let filename = msg
        .filename
        .as_ref()
        .ok_or_else(|| KayaError::Config("Missing filename".to_string()))?;

    let text = msg
        .text
        .as_ref()
        .ok_or_else(|| KayaError::Config("Missing text content".to_string()))?;

    let path = get_meta_dir().join(filename);
    fs::write(&path, text)?;

    Ok(())
}

fn get_all_bookmarked_urls() -> Result<Vec<String>, KayaError> {
    let anga_dir = get_anga_dir();
    if !anga_dir.exists() {
        return Ok(Vec::new());
    }

    let mut urls = Vec::new();

    for entry in fs::read_dir(anga_dir)? {
        let entry = entry?;
        let path = entry.path();

        if path.extension().map(|e| e == "url").unwrap_or(false) {
            if let Ok(content) = fs::read_to_string(&path) {
                for line in content.lines() {
                    if line.starts_with("URL=") {
                        urls.push(line[4..].to_string());
                    }
                }
            }
        }
    }

    Ok(urls)
}

fn read_native_message(stdin: &mut io::StdinLock) -> Result<Option<IncomingMessage>, KayaError> {
    match host::decode_message_opt(stdin, host::MAX_FROM_BROWSER) {
        Ok(Some(json_str)) => {
            let message: IncomingMessage = serde_json::from_str(&json_str)?;
            Ok(Some(message))
        }
        Ok(None) => Ok(None),
        Err(NmError::Disconnected) => Ok(None),
        Err(e) => Err(KayaError::NativeMessaging(e.to_string())),
    }
}

fn write_native_message(
    stdout: &mut io::StdoutLock,
    msg: &OutgoingMessage,
) -> Result<(), KayaError> {
    host::send_json(stdout, msg)?;
    Ok(())
}

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

    let (anga_downloaded, anga_uploaded) = sync_anga(&client, &server, &email, &password)?;
    let (meta_downloaded, meta_uploaded) = sync_meta(&client, &server, &email, &password)?;

    let total_downloaded = anga_downloaded + meta_downloaded;
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

fn sync_anga(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
) -> Result<(usize, usize), KayaError> {
    let url = format!(
        "{}/api/v1/{}/anga",
        server.trim_end_matches('/'),
        urlencoding::encode(email)
    );

    let response = client.get(&url).basic_auth(email, Some(password)).send()?;

    if !response.status().is_success() {
        return Err(KayaError::Http(response.error_for_status().unwrap_err()));
    }

    let server_files: HashSet<String> = parse_server_file_listing(&response.text()?);

    let anga_dir = get_anga_dir();
    let local_files: HashSet<String> = if anga_dir.exists() {
        fs::read_dir(&anga_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_file())
            .filter_map(|e| e.file_name().into_string().ok())
            .filter(|n| !n.starts_with('.'))
            .collect()
    } else {
        HashSet::new()
    };

    let to_download: Vec<_> = server_files.difference(&local_files).collect();
    let to_upload: Vec<_> = local_files.difference(&server_files).collect();

    let downloaded = to_download.len();
    let uploaded = to_upload.len();

    for filename in to_download {
        log::info!("  downloading anga: {}", filename);
        download_anga(client, server, email, password, filename)?;
    }

    for filename in to_upload {
        log::info!("  uploading anga: {}", filename);
        upload_anga(client, server, email, password, filename)?;
    }

    Ok((downloaded, uploaded))
}

fn download_anga(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
    filename: &str,
) -> Result<(), KayaError> {
    let url = format!(
        "{}/api/v1/{}/anga/{}",
        server.trim_end_matches('/'),
        urlencoding::encode(email),
        filename
    );

    let response = client.get(&url).basic_auth(email, Some(password)).send()?;

    if response.status().is_success() {
        let content = response.bytes()?;
        let path = get_anga_dir().join(filename);
        fs::write(path, content)?;
    }

    Ok(())
}

fn upload_anga(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
    filename: &str,
) -> Result<(), KayaError> {
    let path = get_anga_dir().join(filename);
    let content = fs::read(&path)?;

    let url = format!(
        "{}/api/v1/{}/anga/{}",
        server.trim_end_matches('/'),
        urlencoding::encode(email),
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
        log::error!("Failed to upload anga {}: {}", filename, response.status());
    }

    Ok(())
}

fn sync_meta(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
) -> Result<(usize, usize), KayaError> {
    let url = format!(
        "{}/api/v1/{}/meta",
        server.trim_end_matches('/'),
        urlencoding::encode(email)
    );

    let response = client.get(&url).basic_auth(email, Some(password)).send()?;

    if !response.status().is_success() {
        return Err(KayaError::Http(response.error_for_status().unwrap_err()));
    }

    let server_files: HashSet<String> = parse_server_file_listing(&response.text()?);

    let meta_dir = get_meta_dir();
    let local_files: HashSet<String> = if meta_dir.exists() {
        fs::read_dir(&meta_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_file())
            .filter_map(|e| e.file_name().into_string().ok())
            .filter(|n| !n.starts_with('.') && n.ends_with(".toml"))
            .collect()
    } else {
        HashSet::new()
    };

    let to_download: Vec<_> = server_files.difference(&local_files).collect();
    let to_upload: Vec<_> = local_files.difference(&server_files).collect();

    let downloaded = to_download.len();
    let uploaded = to_upload.len();

    for filename in to_download {
        log::info!("  downloading meta: {}", filename);
        download_meta(client, server, email, password, filename)?;
    }

    for filename in to_upload {
        log::info!("  uploading meta: {}", filename);
        upload_meta(client, server, email, password, filename)?;
    }

    Ok((downloaded, uploaded))
}

fn download_meta(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
    filename: &str,
) -> Result<(), KayaError> {
    let url = format!(
        "{}/api/v1/{}/meta/{}",
        server.trim_end_matches('/'),
        urlencoding::encode(email),
        filename
    );

    let response = client.get(&url).basic_auth(email, Some(password)).send()?;

    if response.status().is_success() {
        let content = response.bytes()?;
        let path = get_meta_dir().join(filename);
        fs::write(path, content)?;
    }

    Ok(())
}

fn upload_meta(
    client: &reqwest::blocking::Client,
    server: &str,
    email: &str,
    password: &str,
    filename: &str,
) -> Result<(), KayaError> {
    let path = get_meta_dir().join(filename);
    let content = fs::read(&path)?;

    let url = format!(
        "{}/api/v1/{}/meta/{}",
        server.trim_end_matches('/'),
        urlencoding::encode(email),
        urlencoding::encode(filename)
    );

    let part = reqwest::blocking::multipart::Part::bytes(content)
        .file_name(filename.to_string())
        .mime_str("application/toml")
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
        log::error!("Failed to upload meta {}: {}", filename, response.status());
    }

    Ok(())
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

fn do_install() -> io::Result<()> {
    let exe_path = std::env::current_exe()?;
    println!("Installing native messaging manifests for Save Button...");
    println!("Binary path: {}", exe_path.display());

    install(
        NATIVE_HOST_NAME,
        NATIVE_HOST_DESCRIPTION,
        &exe_path,
        &[CHROME_EXTENSION_ORIGIN.to_string()],
        &[FIREFOX_EXTENSION_ID.to_string()],
        ALL_BROWSERS,
        Scope::User,
    )?;

    extra_browsers::install_extra(NATIVE_HOST_NAME)?;

    println!("Native messaging manifests installed for all supported browsers.");
    Ok(())
}

fn do_uninstall() -> io::Result<()> {
    println!("Removing native messaging manifests for Save Button...");
    remove(NATIVE_HOST_NAME, ALL_BROWSERS, Scope::User)?;
    extra_browsers::uninstall_extra(NATIVE_HOST_NAME)?;
    println!("Native messaging manifests removed.");
    Ok(())
}

fn main() {
    let cli = Cli::parse();

    if cli.install {
        if let Err(e) = do_install() {
            eprintln!("Install failed: {}", e);
            std::process::exit(1);
        }
        return;
    }

    if cli.uninstall {
        if let Err(e) = do_uninstall() {
            eprintln!("Uninstall failed: {}", e);
            std::process::exit(1);
        }
        return;
    }

    // Normal native messaging host mode
    setup_logging();

    if let Err(e) = ensure_directories() {
        log::error!("Failed to create directories: {}", e);
        std::process::exit(1);
    }

    log::info!("Save Button native host started");

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

    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut stdin_lock = stdin.lock();
    let mut stdout_lock = stdout.lock();

    loop {
        match read_native_message(&mut stdin_lock) {
            Ok(Some(msg)) => {
                let id = msg.id;
                let triggers_sync = matches!(msg.message.as_str(), "anga" | "meta");

                let response = if msg.message == "config_status" {
                    match handle_config_status(&msg) {
                        Ok(has_password) => OutgoingMessage {
                            id,
                            success: true,
                            error: None,
                            urls: None,
                            message_type: None,
                            has_password: Some(has_password),
                        },
                        Err(e) => OutgoingMessage {
                            id,
                            success: false,
                            error: Some(e.to_string()),
                            urls: None,
                            message_type: None,
                            has_password: None,
                        },
                    }
                } else {
                    let result = match msg.message.as_str() {
                        "config" => handle_config_message(&msg),
                        "test_connection" => handle_test_connection(&msg),
                        "anga" => handle_anga_message(&msg),
                        "meta" => handle_meta_message(&msg),
                        other => Err(KayaError::Config(format!(
                            "Unknown message type: {}",
                            other
                        ))),
                    };

                    match result {
                        Ok(_) => {
                            let urls = get_all_bookmarked_urls().ok();
                            OutgoingMessage {
                                id,
                                success: true,
                                error: None,
                                urls,
                                message_type: Some("bookmarks".to_string()),
                                has_password: None,
                            }
                        }
                        Err(e) => OutgoingMessage {
                            id,
                            success: false,
                            error: Some(e.to_string()),
                            urls: None,
                            message_type: None,
                            has_password: None,
                        },
                    }
                };

                if let Err(e) = write_native_message(&mut stdout_lock, &response) {
                    log::error!("Failed to write response: {}", e);
                }

                // Immediate sync after anga/meta save for MV3 suspension resilience
                if triggers_sync && response.success {
                    if let Err(e) = sync_with_server() {
                        log::error!("Immediate sync error: {}", e);
                    }
                }
            }
            Ok(None) => {
                running.store(false, Ordering::Relaxed);
                log::info!("Save Button native host shutting down");
                break;
            }
            Err(e) => {
                log::error!("Error reading message: {}", e);
                let response = OutgoingMessage {
                    id: None,
                    success: false,
                    error: Some(e.to_string()),
                    urls: None,
                    message_type: None,
                    has_password: None,
                };
                let _ = write_native_message(&mut stdout_lock, &response);
            }
        }
    }
}
