require 'rubytus/configuration'

module Rubytus
  class Server
    def initialize(app)
      @app = app
      @configuration = self.class.configuration
      @configuration.validates!
      @store = Store.new(@configuration)
    end

    def call(env)
      @request = Request.new(env, @configuration)
      status, header, body = @app.call(env)
      @response = Response.new(body, status, header)

      begin
        process_request
      rescue PermissionError => e
        @response.server_error!
      rescue HeaderError => e
        @response.bad_request!
        @response.write(e.message)
      end

      @response.finish
    end

    attr_reader :request, :response, :store

    def process_request
      if request.collection?
        if request.options?
          response.ok!
          response.date
          response.write('')
        end

        if request.post?
          create_resource
        end

        unless request.options? or request.post?
          response.method_not_allowed!
          response['Allow'] = 'POST'
          response.write "#{request.request_method} used against file creation url. Only POST is allowed."
        end
      end

      if request.resource?
        head_resource  if request.head?
        patch_resource if request.patch?
        get_resource   if request.get?

        unless request.options? or request.head? or request.patch? or request.get?
          allowed = 'HEAD,PATCH'
          response.method_not_allowed!
          response['Allow'] = allowed
          response.write "#{request.request_method} used against file creation url. Allowed: #{allowed}"
        end
      end

      if request.unknown?
        response.not_found!
        response.write("unknown url: #{request.path} - does not match file pattern")
      end
    end

    def create_resource
      uid = generate_uid

      store.create_file(uid, final_length: request.final_length)

      response.created!
      response.date
      response['Location'] = request.resource_url(uid)
    end

    def head_resource
      info = store.read_info(request.resource_name)

      response.ok!
      response.date
      response.write('')
      response.without_content_type
      response.offset(info['Offset'])
    end

    def patch_resource
      response.ok!
    end

    def get_resource(resource)
      response.ok!
      response.write(resource)
    end

    def generate_uid
      Rubytus::Uid::uid
    end

    def self.configure(&block)
      yield(configuration)
      configuration
    end

    def self.configuration
      @@configuration ||= Configuration.new
    end
  end
end
