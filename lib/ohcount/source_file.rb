module Ohcount

	# SourceFile abstracts a source code file and allows easy querying of ohcount-related
	# information.
	#
	# It provides some abstractions to enable ohloh to call it in its own, weird, way.
	# For example, in simple usage scenarios, the SimpleFileContext can simply point
	# to an actual file on disk. In more complex scenarios, the context allows the
	# file contents to be delivered to ohcount from a temp file or in-memory cache.
	#
	class SourceFile
		# The filename we're dealing with.
		attr_reader :filename

		# An array of names of other files in the source tree which
		# may be helpful when disambiguating the language used by the target file.
		# For instance, the presence of an Objective-C *.m file is a clue when
		# determining the language used in a *.h header file.
		# This array is optional, but language identification may be less accurate
		# without it.
		attr_reader :filenames

		# The location on disk where the file content can currently be found.
		# This might not be the same as the original name of the file.
		# For example, file content might be stored in temporary directory.
		attr_reader :file_location

		# At a minimum, you must provide the filename.
		#
		# You may also optionally pass an array of names of other files in the source tree.
		# This will assist when disambiguating the language used by the source file.
		# If you do not include this array, language identification may be less accurate.
		#
		# The SimpleFileContext must provide access to the file content. You can do this
		# by one of three means, which will be probed in the following order:
		#
		# 1. You may optionally pass the content of the source file as string +cached_contents+.
		#
		# 2. You may optionally provide +file_location+ as the name of a file on disk
		#    which contains the content of this source file.
		#
		# 3. If you do neither 1 nor 2, then +filename+ will be assumed to be an actual file on
		#    disk which can be read.
		#
		def initialize(filename, options = {})
			@filename      = filename
			@filenames     = options[:filenames] || []
			@contents      = options[:contents]
			@file_location = options[:file_location] || @filename
		end

		def contents
			@contents ||= File.open(@file_location || @filename) do |io|
				io.read
			end
		end

		def polyglot
			@polyglot ||= Ohcount::Detector::Base.detect(self)
		end

		def basename
			File.basename(filename)
		end

		# returns TRUE if this source_file is recognized as being
		# some type of source code
		def source_code?
			!!polyglot
		end

		def parse
			# dont reparse for nothing
			return if parsed? && !block_given?

			@languages = {}
			return unless polyglot
			Ohcount::parse(contents, polyglot) do |language, semantic, line|
				@languages[language] ||= HashWithDotAccess.new
				@languages[language][semantic] ||= ''
				@languages[language][semantic] << line
				yield(language, semantic, line) if block_given?
			end
		end

		def parsed?
			!(@languages.nil?)
		end

		def languages
			parse unless @languages
			@languages.keys
		end

		def licenses
			@licenses ||= begin
				comments = ''
				parse do |language, semantic, line|
					next unless semantic == :comment
					# Strip leading punctuation.
					comments << ' ' + $1 if line =~ /^[\s[:punct:]]*(.*?)$/
				end
				LicenseSniffer.sniff(comments)
			end
		end

		def raw_entities(&block)
			return unless source_code?
			Ohcount::parse_entities(contents, polyglot, &block)
		end

		# we support sourcefile.ruby
		def method_missing(method, *args)
			parse	
			return @languages[method] || HashWithDotAccess.new
		end

	end
end

class HashWithDotAccess < Hash
	def method_missing(method, *args)
		self[method] if args.empty?
	end
end
