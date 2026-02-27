#!/usr/bin/env ruby
# frozen_string_literal: true

# Release Script
# Bumps the patch version across all extension version files, commits, tags, and pushes.
#
# Usage:
#   ruby bin/release.rb
#
# The script:
#   1. Finds the highest semver tag (e.g. v0.2.13)
#   2. Bumps the patch number (e.g. 0.2.14)
#   3. Updates version in:
#      - extension/package.json
#      - safari/Save Button/Save Button.xcodeproj/project.pbxproj (MARKETING_VERSION, CURRENT_PROJECT_VERSION)
#   4. Commits the changes
#   5. Tags it (e.g. v0.2.14)
#   6. Pushes the tag to origin

REPO_ROOT = File.expand_path("..", __dir__)
PACKAGE_JSON_PATH = File.join(REPO_ROOT, "extension/package.json")
PBXPROJ_PATH = File.join(REPO_ROOT, "safari/Save Button/Save Button.xcodeproj/project.pbxproj")

VERSION_FILES = [PACKAGE_JSON_PATH, PBXPROJ_PATH].freeze

def run(cmd)
  output = `#{cmd} 2>&1`.strip
  unless $?.success?
    abort "Command failed: #{cmd}\n#{output}"
  end
  output
end

def highest_tag
  tags = `git tag -l "v*"`.strip.split("\n").map(&:strip).reject(&:empty?)

  semver_tags = tags.filter_map do |tag|
    if tag.match?(/\Av\d+\.\d+\.\d+\z/)
      parts = tag.delete_prefix("v").split(".").map(&:to_i)
      { tag: tag, major: parts[0], minor: parts[1], patch: parts[2] }
    end
  end

  abort "No semver tags found (expected tags like v0.1.0)" if semver_tags.empty?

  semver_tags.sort_by { |t| [t[:major], t[:minor], t[:patch]] }.last
end

def bump_patch(current)
  { major: current[:major], minor: current[:minor], patch: current[:patch] + 1 }
end

def version_string(v)
  "#{v[:major]}.#{v[:minor]}.#{v[:patch]}"
end

def tag_string(v)
  "v#{version_string(v)}"
end

def update_package_json(old_version, new_version)
  content = File.read(PACKAGE_JSON_PATH)
  updated = content.sub(/"version":\s*"#{Regexp.escape(old_version)}"/, "\"version\": \"#{new_version}\"")
  abort "package.json was not changed — expected version #{old_version}" if updated == content
  File.write(PACKAGE_JSON_PATH, updated)
end

def update_pbxproj(old_version, new_version)
  return unless File.exist?(PBXPROJ_PATH)

  content = File.read(PBXPROJ_PATH)
  updated = content.gsub("MARKETING_VERSION = #{old_version};", "MARKETING_VERSION = #{new_version};")
  if updated == content
    puts "  Warning: project.pbxproj unchanged (no MARKETING_VERSION = #{old_version} found)"
    return
  end

  # Also set CURRENT_PROJECT_VERSION (CFBundleVersion) to the same version string.
  # App Store Connect requires this to increase with each upload.
  updated = updated.gsub(/CURRENT_PROJECT_VERSION = [^;]+;/, "CURRENT_PROJECT_VERSION = #{new_version};")

  count = content.scan("MARKETING_VERSION = #{old_version};").length
  File.write(PBXPROJ_PATH, updated)
  count
end

def current_version_from_package_json
  content = File.read(PACKAGE_JSON_PATH)
  m = content.match(/"version":\s*"([^"]+)"/)
  abort "Could not read version from package.json" unless m
  m[1]
end

# --- Main ---

current = highest_tag
new_ver = bump_patch(current)
new_version = version_string(new_ver)
new_tag = tag_string(new_ver)
old_version = current_version_from_package_json

puts "Current highest tag: #{current[:tag]}"
puts "Current version in package.json: #{old_version}"
puts

print "New version [#{new_version}]: "
override = $stdin.gets.chomp
unless override.empty?
  abort "Invalid version: #{override}" unless override.match?(/\A\d+\.\d+\.\d+\z/)
  new_version = override
  new_tag = "v#{new_version}"
end

puts "Version: #{new_version}"
puts "Tag: #{new_tag}"
puts
puts "Files to update:"
VERSION_FILES.each do |f|
  short = f.sub("#{REPO_ROOT}/", "")
  exists = File.exist?(f) ? "ok" : "missing (skipped)"
  puts "  #{short} [#{exists}]"
end
puts

print "Proceed? [y/N] "
answer = $stdin.gets.chomp
abort "Aborted." unless answer.downcase == "y"
puts

# Check for uncommitted changes (besides the files we're about to modify)
status = `git status --porcelain`.strip
dirty_files = status.split("\n").reject do |line|
  VERSION_FILES.any? { |f| line.end_with?(f.sub("#{REPO_ROOT}/", "")) }
end
unless dirty_files.empty?
  abort "Working tree has uncommitted changes:\n#{dirty_files.join("\n")}\nPlease commit or stash them first."
end

update_package_json(old_version, new_version)
puts "Updated extension/package.json: #{old_version} -> #{new_version}"

pbx_count = update_pbxproj(old_version, new_version)
puts "Updated project.pbxproj: #{pbx_count} MARKETING_VERSION entries" if pbx_count

git_files = ["extension/package.json"]
git_files << PBXPROJ_PATH if File.exist?(PBXPROJ_PATH)

run("git add #{git_files.map { |f| %("#{f}") }.join(" ")}")
run("git commit -m 'v#{new_version}'")
puts "Committed."

run("git tag #{new_tag}")
puts "Tagged #{new_tag}."

run("git push origin main")
run("git push origin #{new_tag}")
puts "Pushed #{new_tag} to origin."

puts
puts "Release #{new_tag} complete."
