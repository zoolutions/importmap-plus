require "open3"
require "tmpdir"

# Minifies a vendored package with whichever JavaScript minifier is installed:
# bun, esbuild or terser, looked up in node_modules/.bin and then on PATH.
# Every tool runs in transform-only mode, so bare import specifiers are left
# exactly as the CDN resolved them and the import map keeps working.
class Importmap::Minifier
  Error = Class.new(StandardError)

  TOOLS = {
    "bun"     => ->(input, output) { [ "build", "--no-bundle", "--minify", "--format=esm", "--target=browser", input, "--outfile=#{output}" ] },
    "esbuild" => ->(input, output) { [ input, "--minify", "--format=esm", "--outfile=#{output}" ] },
    "terser"  => ->(input, output) { [ input, "--module", "--compress", "--mangle", "--output", output ] }
  }.freeze # :nodoc:

  class << self
    def detect
      TOOLS.keys.find { |tool| executable_for(tool) }
    end

    def available?
      !detect.nil?
    end

    def executable_for(tool)
      directories = [ File.expand_path(File.join("node_modules", ".bin")), *ENV["PATH"].to_s.split(File::PATH_SEPARATOR) ]

      directories.each do |directory|
        command_extensions.each do |extension|
          candidate = File.join(directory, "#{tool}#{extension}")
          return candidate if File.file?(candidate) && File.executable?(candidate)
        end
      end

      nil
    end

    # On Windows npm installs these tools as .cmd shims, so the bare name
    # never resolves. Elsewhere the extensionless name is the only candidate.
    def command_extensions
      return [ "" ] unless Gem.win_platform?

      [ "", *ENV.fetch("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";") ]
    end
  end

  attr_reader :tool

  # Pass a tool name to force one, or nothing to use the first one found.
  def initialize(tool = :auto)
    @tool = tool == :auto ? self.class.detect : tool
  end

  def call(source)
    executable = tool && self.class.executable_for(tool)

    unless executable
      raise Error, "No JavaScript minifier found: install bun, esbuild or terser (globally or in node_modules/.bin)"
    end

    Dir.mktmpdir("importmap-minify") do |directory|
      input  = File.join(directory, "package.js")
      output = File.join(directory, "package.min.js")
      File.write(input, source)

      _stdout, stderr, status = Open3.capture3(executable, *TOOLS.fetch(tool).call(input, output))

      unless status.success? && File.exist?(output)
        raise Error, "#{tool} failed to minify: #{stderr.strip}"
      end

      File.read(output)
    end
  end
end
