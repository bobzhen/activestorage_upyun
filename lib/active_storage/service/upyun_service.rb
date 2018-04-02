module ActiveStorage
  # Wraps the upyun Storage Service as an Active Storage service.
  # See ActiveStorage::Service for the generic API documentation that applies to all services.
  #
  #  you can set-up upyun storage service through the generated <tt>config/storage.yml</tt> file.
  #  For example:
  #
  #   upyun:
  #     service: Upyun
  #     bucket: <%= ENV['UPYUUN_BUCKET'] %>
  #     operator: <%= ENV['UPYUUN_OPERATOR'] %>
  #     password: <%= ENV['UPYUUN_PASSWORD'] %>
  #     host: <%= ENV['UPYUN_HOST'] %>
  #     folder: <%= ENV['UPYUN_FOLDER'] %>
  #
  # Then, in your application's configuration, you can specify the service to
  # use like this:
  #
  #   config.active_storage.service = :upyun
  #
  #
  class Service::UpyunService < Service
    ENDPOINT = 'http://v0.api.upyun.com'

    attr_reader :upyun, :bucket, :operator, :password, :host, :folder, :upload_options

    def initialize(bucket:, operator:, password:, host:, folder:, **options)
      @bucket = bucket
      @host = host
      @folder = folder
      @operator = operator
      @password = password
      @upload_options = options
      @upyun = Upyun::Rest.new(bucket, operator, password, options)
    end

    def upload(key, io, checksum: nil)
      instrument :upload, key: key, checksum: checksum do
        begin
          result = @upyun.put(path_for(key), io)
          result
        rescue
          raise ActiveStorage::IntegrityError
        end
      end
    end

    def delete(key)
      instrument :delete, key: key do
        @upyun.delete(path_for(key))
      end
    end

    def download(key)
      instrument :download, key: key do
        io = @upyun.get(path_for(key))
        if block_given?
          yield io
        else
          io
        end
      end
    end

    def exist?(key)
      instrument :exist, key: key do |payload|
        answer = upyun.getinfo(path_for(key))
        result = answer[:error].nil?
        payload[:exist] = result
        result
      end
    end

    def url(key, expires_in:, filename:, content_type:, disposition:)
      instrument :url, key: key do |payload|
        params = {}
        if filename.to_s.include?("x-upyun-process")
          params["x-upyun-process"] = filename.to_s.split("=").last
        end
        url = url_for(key, params: params)
        payload[:url] = url
        url
      end
    end

    def url_for_direct_upload(key, expires_in:, content_type:, content_length:, checksum:)
      instrument :url, key: key do |payload|
        url = [ENDPOINT, @bucket , @folder, key].join('/')
        payload[:url] = url
        url
      end
    end

    def headers_for_direct_upload(key, content_type:, checksum:, content_length:, **)
      user = @operator
      pwd = md5(@password)
      method = 'PUT'
      uri = ["/#{@bucket}", @folder, key].join('/')
      date = gmdate

      str = [method, uri, date].join("&")
      signature = Base64.strict_encode64(
        OpenSSL::HMAC.digest('sha1', pwd, str)
      )
      auth = "UPYUN #{@operator}:#{signature}"
      {"Content-Type" => content_type, "Authorization" => auth, "X-Date" => date}
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
         items = @upyun.getlist "/#{@folder}/#{prefix}"
         unless items[:error]
          items.each do |file|
           @upyun.delete("/#{@folder}/#{prefix}#{file[:name]}")
          end
         end
          @upyun.delete("/#{@folder}/#{prefix}")
      end
    end

    private

    def url_for(key, params: {})
      url = [@host, @folder, key].join('/')
      [url, params['x-upyun-process']].join if params['x-upyun-process']
    end

    def path_for(key)
      [@folder, key].join('/')
    end

    def fullpath(path)
      decoded = URI::encode(URI::decode(path.to_s.force_encoding('utf-8')))
      decoded = decoded.gsub('[', '%5B').gsub(']', '%5D')
      "/#{@bucket}#{decoded.start_with?('/') ? decoded : '/' + decoded}"
    end

    def md5(str)
      Digest::MD5.hexdigest(str)
    end

    def gmdate
      Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT')
    end
  end
end