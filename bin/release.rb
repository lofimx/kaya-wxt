#!/usr/bin/env ruby
# frozen_string_literal: true

# Release Script
# Bumps the patch version in extension/package.json, commits, tags, and pushes.
#
# Usage:
#   ruby bin/release.rb
#
# The script:
#   1. Finds the highest semver tag (e.g. v0.2.13)
#   2. Bumps the patch number (e.g. 0.2.14)
#   3. Updates "version" in extension/package.json
#   4. Commits the change
#   5. Tags it (e.g. v0.2.14)
#   6. Pushes the tag to origin

PACKAGE_JSON_PATH = File.expand_path("../extension/package.json", __dir__)

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

def update_package_json(new_version)
  content = File.read(PACKAGE_JSON_PATH)

  old_version = content.match(/"version":\s*"([^"]+)"/)[1]
  updated = content.sub(/"version":\s*"[^"]+"/, "\"version\": \"#{new_version}\"")

  abort "package.json was not changed — version regex may be wrong" if updated == content

  File.write(PACKAGE_JSON_PATH, updated)

  old_version
end

# --- Main ---

current = highest_tag
new_ver = bump_patch(current)
new_version = version_string(new_ver)
new_tag = tag_string(new_ver)

puts "Current highest tag: #{current[:tag]}"
puts "New version: #{new_version}"
puts "New tag: #{new_tag}"
puts

print "Proceed? [y/N] "
answer = $stdin.gets.chomp
abort "Aborted." unless answer.downcase == "y"
puts

# Check for uncommitted changes (besides package.json itself)
status = `git status --porcelain`.strip
dirty_files = status.split("\n").reject { |line| line.end_with?("extension/package.json") }
unless dirty_files.empty?
  abort "Working tree has uncommitted changes:\n#{dirty_files.join("\n")}\nPlease commit or stash them first."
end

old_version = update_package_json(new_version)
puts "Updated extension/package.json: #{old_version} -> #{new_version}"

run("git add extension/package.json")
run("git commit -m 'v#{new_version}'")
puts "Committed."

run("git tag #{new_tag}")
puts "Tagged #{new_tag}."

run("git push origin main")
run("git push origin #{new_tag}")
puts "Pushed #{new_tag} to origin."

puts
puts "Release #{new_tag} complete."
