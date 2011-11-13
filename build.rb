#!/usr/bin/env ruby
require 'json'
require 'date'
require 'optparse'


#
# Config
#

DOWNLOAD_URL = "https://github.com/emacsmirror/emacs/tarball/%s"
LATEST_URL   = "https://api.github.com/repos/emacsmirror/emacs/commits?sha=%s"

ROOT_DIR    = File.expand_path('..', __FILE__)
TARBALL_DIR = "#{ROOT_DIR}/tarballs"
SOURCES_DIR  = "#{ROOT_DIR}/sources"
BUILDS_DIR  = "#{ROOT_DIR}/builds"


#
# Main
#

def main
  opts = parse_options

  ref  = ARGV.shift
  meta = get_ref_info(ref)

  if meta['sha'] && meta['date']
    tarball = download_tarball(meta['sha'])
    source  = extract_tarball(tarball, patches(opts))
    app     = compile_source(source)

    archive_app(app, meta['sha'], meta['date'])
  else
    raise "\nERROR: Failed to get commit info from GitHub API."
  end
end


#
# Patches
#

def patches(opts = {})
  p = []

  if !opts[:no_fullscreen]
    p << 'https://raw.github.com/gist/1012927'
  end

  if opts[:srgb]
    p << 'https://raw.github.com/gist/1361934'
  end

  p
end


#
# Options
#

def parse_options
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: build.rb [options] [branch/sha]"

    opts.on('--srgb', "Include sRGB patch.") do
      options[:srgb] = true
    end

    opts.on("--no-fullscreen", "Don't include fullscreen patch") do
      options[:no_fullscreen] = true
    end
  end.parse!

  options
end


#
# Core Methods
#

def download_tarball(sha)
  mkdir TARBALL_DIR

  url = (DOWNLOAD_URL % sha)

  filename = "emacsmirror-emacs-#{sha[0..6]}.tgz"
  target   = File.join(TARBALL_DIR, filename)

  if !File.exist?(target)
    puts "\nDownloading tarball from GitHub. This could take a while, " +
         "please be patient."
    system "curl -L \"#{url}\" -o \"#{target}\""
    raise "\nERROR: Download failed." unless File.exist?(target)
  else
    puts "\nINFO: #{filename} already exists locally, attempting to use."
  end
  target
end

def extract_tarball(filename, patches = [])
  mkdir SOURCES_DIR

  dirname = File.basename(filename).gsub(/\.\w+$/, '')
  target = "#{SOURCES_DIR}/#{dirname}"

  if !File.exist?(target)
    puts "\nExtracting tarball..."
    system "tar -xzf \"#{filename}\" -C \"#{SOURCES_DIR}\""
    raise "\nERROR: Tarball extraction failed." unless File.exist?(target)
    patches.each do |url|
      apply_patch(url, target)
    end
  else
    puts "\nINFO: #{dirname} source tree exists, attempting to use."
  end
  target
end

def compile_source(source)
  target = "#{source}/nextstep"

  if !File.exist?("#{target}/Emacs.app")
    puts "\nCompiling from source. This will take a while..."

    if File.exist? "#{source}/autogen/copy_autogen"
      system "cd \"#{source}\" && autogen/copy_autogen"
    end

    system "cd \"#{source}\" && ./configure --with-ns"
    system "cd \"#{source}\" && make install"

    raise "\nERROR: Build failed." unless File.exist?("#{target}/Emacs.app")
  else
    puts "\nINFO: Emacs.app already exists in " +
         "\"#{target.gsub(ROOT_DIR + '/', '')}\", attempting to use."
  end
  "#{target}/Emacs.app"
end

def archive_app(app, sha, date)
  mkdir BUILDS_DIR

  filename = "Emacs.app-#{date}-(#{sha[0..6]}).tbz"
  target   = "#{BUILDS_DIR}/#{filename}"

  app_base = File.basename(app)
  app_dir  = File.dirname(app)

  if !File.exist?(target)
    puts "\nCreating #{filename} archive in \"#{BUILDS_DIR}\"..."
    system "cd \"#{app_dir}\" && tar -cjf \"#{target}\" \"#{app_base}\""
  else
    puts "\nINFO: #{filename} archive exists in " +
         "#{BUILDS_DIR.gsub(ROOT_DIR + '/', '')}, skipping archving."
  end
end


#
# Helper Methods
#

def mkdir(dir)
  system "mkdir -p \"#{dir}\""
end

def get_ref_info(ref = 'master')
  response = `curl "#{LATEST_URL % ref}" 2>/dev/null`
  meta = JSON.parse(response).first
  return {
    'sha' => meta['sha'],
    'date' => Date.parse(meta['commit']['committer']['date'])
  }
end

def apply_patch(url, target)
  raise "ERROR: \"#{target}\" does not exist." unless File.exist?(target)
  system "mkdir -p \"#{target}/patches\""

  patch_file = "#{target}/patches/patch-{num}.diff"
  num = 1
  while File.exist? patch_file.gsub('{num}', num.to_s.rjust(3, '0'))
    num += 1
  end
  patch_file.gsub!('{num}', num.to_s.rjust(3, '0'))

  puts "Downloading patch: #{url}"
  system "curl -L# \"#{url}\" -o \"#{patch_file}\""

  puts "Applying patch..."
  system "cd \"#{target}\" && patch -f -p1 -i \"#{patch_file}\""
end


#
# Run it!
#

main
