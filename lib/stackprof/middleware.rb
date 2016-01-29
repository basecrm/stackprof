require 'fileutils'

module StackProf
  class Middleware
    def initialize(app, options = {})
      @app       = app
      @options   = options
      @num_reqs  = options[:save_every] || nil

      Middleware.mode     = options[:mode] || :cpu
      Middleware.interval = options[:interval] || 1000
      Middleware.raw      = options[:raw] || false
      Middleware.enabled  = options[:enabled]
      Middleware.path     = options[:path] || 'tmp'
      at_exit{ Middleware.save } if options[:save_at_exit]
    end

    def call(env)
      enabled = Middleware.enabled?(env)
      if enabled
        StackProf.start(mode: Middleware.mode, interval: Middleware.interval, raw: Middleware.raw)
        start_time = Time.now.to_f
      end
      @app.call(env)
    ensure
      if enabled
        request_time = Time.now.to_f - start_time
        StackProf.stop
        if @num_reqs && (@num_reqs-=1) == 0
          @num_reqs = @options[:save_every]

          if @options[:save_every] == 1
            filename = Middleware.filename_with_request(request_time, env['REQUEST_PATH'])
          end

          Middleware.save(filename)
        end
      end
    end

    class << self
      attr_accessor :enabled, :mode, :interval, :raw, :path

      def enabled?(env)
        if enabled.respond_to?(:call)
          enabled.call(env)
        else
          enabled
        end
      end

      def save(filename = nil)
        if results = StackProf.results
          FileUtils.mkdir_p(Middleware.path)
          filename ||= default_filename
          File.open(File.join(Middleware.path, filename), 'wb') do |f|
            f.write Marshal.dump(results)
          end
          filename
        end
      end

      def filename_with_request(request_time, request_path)
        time = (request_time * 1000).to_i
        path = request_path.gsub(/[\/\.]/, '-')
        "stackprof-#{Time.now.to_i}-#{Middleware.mode}-#{time}#{path}.dump"
      end

      def default_filename
        "stackprof-#{Middleware.mode}-#{Process.pid}-#{Time.now.to_i}.dump"
      end

    end
  end
end
