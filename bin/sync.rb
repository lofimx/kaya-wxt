#!/usr/bin/env ruby
# frozen_string_literal: true

# Kaya Sync Script
# Synchronizes local ~/.kaya/ directory with the Kaya server API
#
# Directory structure:
#   ~/.kaya/anga/  - bookmarks, notes, PDFs, images, and other files
#   ~/.kaya/meta/  - human tags and metadata for anga records (TOML files)

require "net/http"
require "uri"
require "json"
require "fileutils"
require "optparse"
require "io/console"
require "securerandom"

class KayaSync
  DEFAULT_URL = "https://kaya.town"
  KAYA_DIR = File.expand_path("~/.kaya")
  ANGA_DIR = File.join(KAYA_DIR, "anga")
  META_DIR = File.join(KAYA_DIR, "meta")

  def initialize(options)
    @email = options[:email]
    @password = options[:password]
    @base_url = options[:url] || DEFAULT_URL
    @verbose = options[:verbose]

    @stats = {
      anga: { downloaded: [], uploaded: [], errors: [] },
      meta: { downloaded: [], uploaded: [], errors: [] }
    }
  end

  def run
    prompt_credentials
    ensure_local_dirs

    log "Connecting to #{@base_url}..."
    log "Syncing files for #{@email}"
    log ""

    sync_anga
    sync_meta

    print_summary
  end

  private

  def prompt_credentials
    unless @email
      print "Email: "
      @email = $stdin.gets.chomp
    end

    unless @password
      print "Password: "
      @password = $stdin.noecho(&:gets).chomp
      puts
    end
  end

  def ensure_local_dirs
    FileUtils.mkdir_p(ANGA_DIR)
    FileUtils.mkdir_p(META_DIR)
  end

  # ============================================================================
  # Anga Sync
  # ============================================================================

  def sync_anga
    log "--- Syncing Anga (files) ---"

    server_files = fetch_server_anga_files
    local_files = fetch_local_anga_files

    files_to_download = server_files - local_files
    files_to_upload = local_files - server_files

    log "Server has #{server_files.size} anga files"
    log "Local has #{local_files.size} anga files"
    log "To download: #{files_to_download.size}"
    log "To upload: #{files_to_upload.size}"
    log ""

    download_anga_files(files_to_download)
    upload_anga_files(files_to_upload)
  end

  def fetch_server_anga_files
    uri = URI("#{@base_url}/api/v1/#{URI.encode_www_form_component(@email)}/anga")

    response = make_request(:get, uri)

    if response.is_a?(Net::HTTPSuccess)
      # Server returns URL-encoded filenames, decode them for comparison
      response.body.split("\n").map { |f| URI.decode_www_form_component(f.strip) }.reject(&:empty?)
    else
      log_error "Failed to fetch server anga list: #{response.code} #{response.message}"
      exit 1
    end
  end

  def fetch_local_anga_files
    return [] unless Dir.exist?(ANGA_DIR)

    Dir.entries(ANGA_DIR)
       .reject { |f| f.start_with?(".") }
       .select { |f| File.file?(File.join(ANGA_DIR, f)) }
  end

  def download_anga_files(files)
    files.each do |filename|
      download_anga_file(filename)
    end
  end

  def download_anga_file(filename)
    uri = URI("#{@base_url}/api/v1/#{URI.encode_www_form_component(@email)}/anga/#{URI.encode_www_form_component(filename)}")

    response = make_request(:get, uri)

    if response.is_a?(Net::HTTPSuccess)
      local_path = File.join(ANGA_DIR, filename)
      File.binwrite(local_path, response.body)
      log "[ANGA DOWNLOAD] #{filename}"
      @stats[:anga][:downloaded] << filename
    else
      log_error "[ANGA DOWNLOAD FAILED] #{filename}: #{response.code} #{response.message}"
      @stats[:anga][:errors] << { file: filename, operation: :download, error: "#{response.code} #{response.message}" }
    end
  end

  def upload_anga_files(files)
    files.each do |filename|
      upload_anga_file(filename)
    end
  end

  def upload_anga_file(filename)
    local_path = File.join(ANGA_DIR, filename)
    uri = URI("#{@base_url}/api/v1/#{URI.encode_www_form_component(@email)}/anga/#{URI.encode_www_form_component(filename)}")

    file_content = File.binread(local_path)
    content_type = mime_type_for(filename)

    response = make_request(:post, uri, file_content, content_type, filename)

    case response
    when Net::HTTPCreated, Net::HTTPSuccess
      log "[ANGA UPLOAD] #{filename}"
      @stats[:anga][:uploaded] << filename
    when Net::HTTPConflict
      log "[ANGA SKIP] #{filename} (already exists on server)"
    when Net::HTTPExpectationFailed
      log_error "[ANGA UPLOAD FAILED] #{filename}: Filename mismatch"
      @stats[:anga][:errors] << { file: filename, operation: :upload, error: "Filename mismatch" }
    else
      log_error "[ANGA UPLOAD FAILED] #{filename}: #{response.code} #{response.message}"
      @stats[:anga][:errors] << { file: filename, operation: :upload, error: "#{response.code} #{response.message}" }
    end
  end

  # ============================================================================
  # Meta Sync
  # ============================================================================

  def sync_meta
    log "--- Syncing Meta (tags/metadata) ---"

    server_files = fetch_server_meta_files
    local_files = fetch_local_meta_files

    files_to_download = server_files - local_files
    files_to_upload = local_files - server_files

    log "Server has #{server_files.size} meta files"
    log "Local has #{local_files.size} meta files"
    log "To download: #{files_to_download.size}"
    log "To upload: #{files_to_upload.size}"
    log ""

    download_meta_files(files_to_download)
    upload_meta_files(files_to_upload)
  end

  def fetch_server_meta_files
    uri = URI("#{@base_url}/api/v1/#{URI.encode_www_form_component(@email)}/meta")

    response = make_request(:get, uri)

    if response.is_a?(Net::HTTPSuccess)
      # Server returns URL-encoded filenames, decode them for comparison
      response.body.split("\n").map { |f| URI.decode_www_form_component(f.strip) }.reject(&:empty?)
    else
      log_error "Failed to fetch server meta list: #{response.code} #{response.message}"
      exit 1
    end
  end

  def fetch_local_meta_files
    return [] unless Dir.exist?(META_DIR)

    Dir.entries(META_DIR)
       .reject { |f| f.start_with?(".") }
       .select { |f| File.file?(File.join(META_DIR, f)) }
       .select { |f| f.end_with?(".toml") }
  end

  def download_meta_files(files)
    files.each do |filename|
      download_meta_file(filename)
    end
  end

  def download_meta_file(filename)
    uri = URI("#{@base_url}/api/v1/#{URI.encode_www_form_component(@email)}/meta/#{URI.encode_www_form_component(filename)}")

    response = make_request(:get, uri)

    if response.is_a?(Net::HTTPSuccess)
      local_path = File.join(META_DIR, filename)
      File.binwrite(local_path, response.body)
      log "[META DOWNLOAD] #{filename}"
      @stats[:meta][:downloaded] << filename
    else
      log_error "[META DOWNLOAD FAILED] #{filename}: #{response.code} #{response.message}"
      @stats[:meta][:errors] << { file: filename, operation: :download, error: "#{response.code} #{response.message}" }
    end
  end

  def upload_meta_files(files)
    files.each do |filename|
      upload_meta_file(filename)
    end
  end

  def upload_meta_file(filename)
    local_path = File.join(META_DIR, filename)
    uri = URI("#{@base_url}/api/v1/#{URI.encode_www_form_component(@email)}/meta/#{URI.encode_www_form_component(filename)}")

    file_content = File.binread(local_path)
    content_type = "application/toml"

    response = make_request(:post, uri, file_content, content_type, filename)

    case response
    when Net::HTTPCreated, Net::HTTPSuccess
      log "[META UPLOAD] #{filename}"
      @stats[:meta][:uploaded] << filename
    when Net::HTTPConflict
      log "[META SKIP] #{filename} (already exists on server)"
    when Net::HTTPExpectationFailed
      log_error "[META UPLOAD FAILED] #{filename}: Filename mismatch"
      @stats[:meta][:errors] << { file: filename, operation: :upload, error: "Filename mismatch" }
    when Net::HTTPUnprocessableEntity
      log_error "[META UPLOAD FAILED] #{filename}: Invalid TOML format"
      @stats[:meta][:errors] << { file: filename, operation: :upload, error: "Invalid TOML format" }
    else
      log_error "[META UPLOAD FAILED] #{filename}: #{response.code} #{response.message}"
      @stats[:meta][:errors] << { file: filename, operation: :upload, error: "#{response.code} #{response.message}" }
    end
  end

  # ============================================================================
  # Common Methods
  # ============================================================================

  def make_request(method, uri, body = nil, content_type = nil, filename = nil)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    request = case method
    when :get
      Net::HTTP::Get.new(uri)
    when :post
      req = Net::HTTP::Post.new(uri)
      if body
        boundary = "----KayaSyncBoundary#{SecureRandom.hex(16)}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = build_multipart_body(boundary, filename, body, content_type)
      end
      req
    end

    request.basic_auth(@email, @password)

    http.request(request)
  rescue StandardError => e
    log_error "Network error: #{e.message}"
    exit 1
  end

  def build_multipart_body(boundary, filename, content, content_type)
    body = []
    body << "--#{boundary}"
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\""
    body << "Content-Type: #{content_type}"
    body << ""
    body << content
    body << "--#{boundary}--"
    body.join("\r\n")
  end

  def mime_type_for(filename)
    ext = File.extname(filename).downcase
    case ext
    when ".md" then "text/markdown"
    when ".url" then "text/plain"
    when ".txt" then "text/plain"
    when ".json" then "application/json"
    when ".toml" then "application/toml"
    when ".pdf" then "application/pdf"
    when ".png" then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".gif" then "image/gif"
    when ".webp" then "image/webp"
    when ".svg" then "image/svg+xml"
    when ".html", ".htm" then "text/html"
    else "application/octet-stream"
    end
  end

  def log(message)
    puts message
  end

  def log_error(message)
    $stderr.puts message
  end

  def print_summary
    total_downloaded = @stats[:anga][:downloaded].size + @stats[:meta][:downloaded].size
    total_uploaded = @stats[:anga][:uploaded].size + @stats[:meta][:uploaded].size
    total_errors = @stats[:anga][:errors].size + @stats[:meta][:errors].size

    log ""
    log "=" * 50
    log "SYNC COMPLETE"
    log "=" * 50
    log ""
    log "Anga (files):"
    log "  Downloaded: #{@stats[:anga][:downloaded].size}"
    log "  Uploaded:   #{@stats[:anga][:uploaded].size}"
    log "  Errors:     #{@stats[:anga][:errors].size}"
    log ""
    log "Meta (tags/metadata):"
    log "  Downloaded: #{@stats[:meta][:downloaded].size}"
    log "  Uploaded:   #{@stats[:meta][:uploaded].size}"
    log "  Errors:     #{@stats[:meta][:errors].size}"
    log ""
    log "Total: #{total_downloaded} downloaded, #{total_uploaded} uploaded, #{total_errors} errors"

    all_errors = @stats[:anga][:errors] + @stats[:meta][:errors]
    if all_errors.any?
      log ""
      log "Errors:"
      all_errors.each do |error|
        log "  - #{error[:operation].upcase} #{error[:file]}: #{error[:error]}"
      end
    end

    log ""
  end
end

# Parse command line options
options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-e", "--email EMAIL", "Your Kaya account email") do |email|
    options[:email] = email
  end

  opts.on("-p", "--password PASSWORD", "Your Kaya account password") do |password|
    options[:password] = password
  end

  opts.on("-u", "--url URL", "Kaya server URL (default: #{KayaSync::DEFAULT_URL})") do |url|
    options[:url] = url.chomp("/")
  end

  opts.on("-v", "--verbose", "Enable verbose output") do
    options[:verbose] = true
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Run sync
KayaSync.new(options).run
