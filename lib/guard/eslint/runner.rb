# coding: utf-8

require 'json'

module Guard
  class Eslint
    # This class runs `eslint` command, retrieves result and notifies.
    # An instance of this class is intended to invoke `eslint` only once in its lifetime.
    class Runner
      def initialize(options)
        @options = options
      end

      def run(paths = [])
        command = build_command(paths)
        passed = system(*command)
        Compat::UI.info "paths #{paths}"

        case @options[:notification]
        when :failed
          notify(passed) unless passed
        when true
          notify(passed)
        end

        passed
      end

      def build_command(paths)
        command = ['eslint']

        command.concat(['**/*.js', '**/*.es6']) if paths.empty?

        command.concat(['-f', 'json', '-o', json_file_path])
        # command << '--force-exclusion'
        command.concat(args_specified_by_user)

        Compat::UI.info "command #{command}"
        command.concat(paths)
      end

      def should_add_default_formatter_for_console?
        !@options[:hide_stdout] && !include_formatter_for_console?(args_specified_by_user)
      end

      def args_specified_by_user
        @args_specified_by_user ||= begin
          args = @options[:cli]
          case args
          when Array    then args
          when String   then args.shellsplit
          when NilClass then []
          else fail ':cli option must be either an array or string'
          end
        end
      end

      def include_formatter_for_console?(cli_args)
        index = -1
        formatter_args = cli_args.group_by do |arg|
          index += 1 if arg == '--format' || arg.start_with?('-f')
          index
        end
        formatter_args.delete(-1)

        formatter_args.each_value.any? do |args|
          args.none? { |a| a == '--out' || a.start_with?('-o') }
        end
      end

      def json_file_path
        @json_file_path ||= begin
          # Just generate random tempfile path.
          basename = self.class.name.downcase.gsub('::', '_')
          tempfile = Tempfile.new(basename)
          tempfile.close
          tempfile.path
        end
      end

      def result
        @result ||= begin
          File.open(json_file_path) do |file|
            # Rubinius 2.0.0.rc1 does not support `JSON.load` with 3 args.
            JSON.parse(file.read, symbolize_names: true)
          end
        end
      end

      def notify(passed)
        image = passed ? :success : :failed
        Notifier.notify(summary_text, title: 'ESLint results', image: image)
      end

      # rubocop:disable Metric/AbcSize
      def summary_text
        summary = {
          files_inspected: result.count,
          errors: result.map { |x| x[:errorCount] }.reduce(:+),
          warnings: result.map { |x| x[:warningCount] }.reduce(:+)
        }

        text = pluralize(summary[:files_inspected], 'file')
        text << ' inspected, '

        errors_count = summary[:errors]
        text << pluralize(errors_count, 'error', no_for_zero: true)
        text << ' detected'

        warning_count = summary[:warnings]
        text << pluralize(warning_count, 'warning', no_for_zero: true)
        text << ' detected'
      end
      # rubocop:enable Metric/AbcSize

      def failed_paths
        result.reject { |f| f[:messages].empty? }.map { |f| f[:filePath] }
      end

      def pluralize(number, thing, options = {})
        text = ''

        if number == 0 && options[:no_for_zero]
          text = 'no'
        else
          text << number.to_s
        end

        text << " #{thing}"
        text << 's' unless number == 1

        text
      end
    end
  end
end
