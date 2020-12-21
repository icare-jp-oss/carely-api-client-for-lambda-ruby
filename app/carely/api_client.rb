# gem
require "bundler/setup"
require 'oauth2'
require "multi_json"
require "yaml/store"
require "json"
require "fileutils"
require "aws-sdk-s3"

require "./app/common/carely_notification"
require "./app/common/common_process"

module App
  module Carely
    class ApiClient
      include App::Common::CarelyNotification
      include App::Common::CommonProcess

      CARELY_API_TOKEN_FILE = "carely_api_token.yml"

      if ENV["execution"].nil?
        CARELY_API_TOKEN_FILE_PATH = "./config/#{CARELY_API_TOKEN_FILE}"
        CARELY_API_ENDPOINT = "https://api.www-demo.carely.io/api/graphql"
        CARELY_SITE_URL = "https://auth.www-demo.carely.io/"
      else
        CARELY_API_TOKEN_FILE_PATH = "/tmp/#{CARELY_API_TOKEN_FILE}"
        CARELY_API_ENDPOINT = "https://api.carely.io/api/graphql"
        CARELY_SITE_URL = "https://auth.carely.io/"
      end

      attr_reader :oauth2_client, :client_id, :client_secret,
                    :token, :refresh_token, :s3_object

      # Set up the OAuth2 client
      def initialize
        if ENV["execution"] == "lambda"
          # S3へGOOGLE_API_TOKEN_FILEが存在していれば取得してtmp領域へコピー
          @s3_object = Aws::S3::Resource.new
          file_object = @s3_object.bucket(ENV["bucket_name"]).object("#{ENV["s3_directory"]}/#{CARELY_API_TOKEN_FILE}")
          if file_object.exists?
            file_object.download_file(CARELY_API_TOKEN_FILE_PATH)
          else
            # 初回起動時は環境変数からtoken情報を取得しファイルへ保存
            token_info = ENV["carely_api_token"]
            FileUtils.touch(CARELY_API_TOKEN_FILE_PATH)
            store = YAML::Store.new(CARELY_API_TOKEN_FILE_PATH)
            token_info_json = JSON.parse(token_info)
            store.transaction do
              store["client_id"] = aes_encrypt(token_info_json["client_id"])
              store["client_secret"] = aes_encrypt(token_info_json["client_secret"])
              store["token"] = aes_encrypt(token_info_json["token"])
              store["refresh_token"] = aes_encrypt(token_info_json["refresh_token"])
            end
            # tmpへ保存したファイルをS3へアップロード
            file_object.upload_file(CARELY_API_TOKEN_FILE_PATH)
          end
        end
        token_yaml_data = YAML.load_file(CARELY_API_TOKEN_FILE_PATH)
        @client_id = aes_decrypt(token_yaml_data["client_id"])
        @client_secret = aes_decrypt(token_yaml_data["client_secret"])
        @token = aes_decrypt(token_yaml_data["token"])
        @refresh_token = aes_decrypt(token_yaml_data["refresh_token"])

        @oauth2_client = OAuth2::Client.new(
          @client_id,
          @client_secret,
          site: CARELY_SITE_URL,
          authorize_url: "corporate_manager/oauth/authorize",
          token_url: "corporate_manager/oauth/token",
          raise_errors: true
        )
      end

      # tokenを検証して有効期限切れであればrefreshする
      def verification_token_and_refresh
        response_body = token_introspect
        # tokenが期限切れの場合はrefresh tokenで再発行
        new_token if response_body["active"] == false
      end

      private

      # access tokenが有効か試す
      def token_introspect
        args = {
          request_uri: "#{CARELY_SITE_URL}corporate_manager/oauth/introspect",
          http_status: "POST",
          post_data: {
            client_id: @client_id,
            client_secret: @client_secret,
            token: @token,
            refresh_token: @refresh_token
          }
        }
        response = build_http_request(args)
        JSON.parse(response.body)
      end

      # refresh tokenにより新しいtokenを取得する
      def new_token
        access_token = OAuth2::AccessToken.new(
          @oauth2_client,
          @token,
          { refresh_token: @refresh_token }
        )
        new_token = access_token.refresh!

        @token = new_token.token
        @refresh_token = new_token.refresh_token
        # Carely api のtoken情報をファイルへ保存
        store = YAML::Store.new(CARELY_API_TOKEN_FILE_PATH)
        store.transaction do
          store["client_id"] = aes_encrypt(@client_id)
          store["client_secret"] = aes_encrypt(@client_secret)
          store["token"] = aes_encrypt(@token)
          store["refresh_token"] = aes_encrypt(@refresh_token)
        end
        if ENV["execution"] == "lambda"
          # S3へ保存
          @s3_object ||= Aws::S3::Resource.new
          file_object = @s3_object.bucket(ENV["bucket_name"]).object("#{ENV["s3_directory"]}/#{CARELY_API_TOKEN_FILE}")
          file_object.upload_file(CARELY_API_TOKEN_FILE_PATH)
        end
      rescue => e
        error_messages = e.message.split("\n")
        carely_notification_error(error_messages[0])
      end

      def build_http_request(args = {})
        retry_count = 0

        begin
          uri = URI.parse(args[:request_uri])
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 120
          http.read_timeout = 120

          case args[:http_status]
          when "POST"
            post_request = Net::HTTP::Post.new(uri.path)
            post_request.set_form_data(args[:post_data])
            http.request(post_request)
          when "GET"
            request = Net::HTTP::Get.new(uri.request_uri)
            request['Authorization'] = "Bearer #{@token}"
            http.request(request)
          else
            ""
          end
        rescue SocketError => e
          if retry_count <= 5
            sleep 3
            retry_count += 1
            puts "build_http_request retry:#{retry_count}"
            retry
          else
            raise e
          end
        end
      end
    end
  end
end
