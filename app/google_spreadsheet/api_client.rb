# gem
require "bundler/setup"
require "google/apis/sheets_v4"
require "googleauth"
require "googleauth/stores/file_token_store"
require "fileutils"
require "active_support"
require "active_support/core_ext"

require "./app/common/carely_notification"
require "./app/common/common_process"

include App::Common::CarelyNotification
include App::Common::CommonProcess

module App
  module GoogleSpreadsheet
    class ApiClient

      HEADER_CHECK_DATA = %w(社員番号 本名 本名(読み) メールアドレス 生年月日 性別 入社年月日 登録グループ 退職日 就業ステータス 業務形態 部署 事業場 役職 集団分析単位名 ストレスチェックの対象)
      HEADER_SYMBOL_DATA = %i(employee_number fullname fullname_ja email born_on gender join_on branch_name retire_on employment_status working_arrangement department_name workplace_name job_title group_analysis_name has_stress_check)
      # { :employee_number=>"社員番号", :fullname=>"本名", :fullname_ja=>"本名(読み)", ・・・ }のようなデータを作成
      HEADER_WAMEI_DATA_FROM_SYMBOL = HEADER_SYMBOL_DATA.zip(HEADER_CHECK_DATA).to_h

      # speradsheetのheaderの場所
      HEADER_LOCATION = "C15:R15".freeze
      # speradsheetのデータの範囲
      DATA_RANGE = "C16:R".freeze

      APPLICATION_NAME = "Google Sheets API Ruby Quickstart"

      # The file token.yaml stores the user's access and refresh tokens, and is
      # created automatically when the authorization flow completes for the first
      # time.
      SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY

      GOOGLE_API_TOKEN_FILE = "google_api_token.yml"
      GOOGLE_API_CREDENTIAL_FILE = "credentials.json"

      if ENV["execution"].nil?
        GOOGLE_API_TOKEN_FILE_PATH = "./config/#{GOOGLE_API_TOKEN_FILE}"
        GOOGLE_API_CREDENTIAL_FILE_PATH = "./config/#{GOOGLE_API_CREDENTIAL_FILE}"
      else
        GOOGLE_API_TOKEN_FILE_PATH = "/tmp/#{GOOGLE_API_TOKEN_FILE}"
        GOOGLE_API_CREDENTIAL_FILE_PATH = "/tmp/#{GOOGLE_API_CREDENTIAL_FILE}"
      end

      attr_reader :google_api_sheets, :spreadsheet_id, :spreadsheet_name

      def initialize
        # spreadsheetのID,シート名の情報を取得します
        spreadsheet_info = File.open("./config/spreadsheet_info.json") do |file|
          tmp = file.read
          JSON.parse(tmp, :symbolize_names => true)
        end
        if ENV["execution"].nil?
          @spreadsheet_id = spreadsheet_info[:development][:spreadsheet_id]
          @spreadsheet_name = spreadsheet_info[:development][:spreadsheet_name]
        else
          @spreadsheet_id = spreadsheet_info[:lambda][:spreadsheet_id]
          @spreadsheet_name = spreadsheet_info[:lambda][:spreadsheet_name]
        end

        # [lambda]tokenファイルはS3へアップロードして管理、credentialsファイルはtmpディレクトリへ保存して管理
        # [local]tokenファイルもcredentialsファイルも./config配下で管理
        if ENV["execution"] == "lambda"
          # S3へGOOGLE_API_TOKEN_FILEが存在しているれば取得してtmp領域へコピー
          s3 = Aws::S3::Resource.new
          file_object = s3.bucket(ENV["bucket_name"]).object("#{ENV["s3_directory"]}/#{GOOGLE_API_TOKEN_FILE}")
          if file_object.exists?
            file_object.download_file(GOOGLE_API_TOKEN_FILE_PATH)
          else
            # 初回起動時は環境変数からtoken情報を取得しファイルへ保存
            token_info = ENV["google_api_token"]
            FileUtils.touch(GOOGLE_API_TOKEN_FILE_PATH)
            store = YAML::Store.new(GOOGLE_API_TOKEN_FILE_PATH)
            store.transaction do
              store["default"] = aes_encrypt(token_info)
            end
            # tmpへ保存したファイルをS3へアップロード
            file_object.upload_file(GOOGLE_API_TOKEN_FILE_PATH)
          end

          # credentialsファイル
          google_api_credential = ENV["google_api_credential"]
          FileUtils.touch(GOOGLE_API_CREDENTIAL_FILE_PATH)
          File.open(GOOGLE_API_CREDENTIAL_FILE_PATH, "w") do |f|
            f.puts(google_api_credential)
          end
        end

        # Initialize the API
        @google_api_sheets = Google::Apis::SheetsV4::SheetsService.new
        @google_api_sheets.client_options.application_name = APPLICATION_NAME
        @google_api_sheets.authorization = authorize
      end

      def read_spreadsheet_data
        # 読み取るセルの範囲を指定
        # headerは15行目。1〜14行目はフリースペース。A、B列は対象外
        header = "#{@spreadsheet_name}!#{HEADER_LOCATION}"
        range = "#{@spreadsheet_name}!#{DATA_RANGE}"
        header_data = google_api_sheets.get_spreadsheet_values(@spreadsheet_id, header)
        # headerのチェック
        carely_notification_error("spreadsheetのheader情報が変更された可能性があります。") && return if header_data.values.flatten != HEADER_CHECK_DATA

        response = google_api_sheets.get_spreadsheet_values(@spreadsheet_id, range)
        carely_notification_error("spreadsheetにデータが存在しません。") && return if response.values.blank?

        icare_data = []
        response.values.each do |row|
          # {:branch_name=>"デモ本社", ・・・ }のように加工
          icare_data << HEADER_SYMBOL_DATA.zip(row).to_h
        end
        icare_data
      end

      private

      ##
      # Ensure valid credentials, either by restoring from the saved credentials
      # files or intitiating an OAuth2 authorization. If authorization is required,
      # the user's default browser will be launched to approve the request.
      #
      # @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
      def authorize
        carely_notification_error("credentials.jsonが存在しません。") && return unless File.exist?(GOOGLE_API_CREDENTIAL_FILE_PATH)
        carely_notification_error("google_api_token.ymlが存在しません。") && return unless File.exist?(GOOGLE_API_TOKEN_FILE_PATH)

        aes_decrypt_token_file(GOOGLE_API_TOKEN_FILE_PATH)

        client_id = Google::Auth::ClientId.from_file(GOOGLE_API_CREDENTIAL_FILE_PATH)
        token_store = Google::Auth::Stores::FileTokenStore.new(file: GOOGLE_API_TOKEN_FILE_PATH)
        authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)

        user_id = "default"
        credentials = authorizer.get_credentials(user_id)

        # 上記操作でGOOGLE_API_TOKEN_FILEが更新されるのでlambda上ではGOOGLE_API_TOKEN_FILEをS3へupload
        if ENV["execution"] == "lambda"
          s3 = Aws::S3::Resource.new
          file_object = s3.bucket(ENV["bucket_name"]).object("#{ENV["s3_directory"]}/#{GOOGLE_API_TOKEN_FILE}")
          aes_encrypt_token_file(GOOGLE_API_TOKEN_FILE_PATH)
          file_object.upload_file(GOOGLE_API_TOKEN_FILE_PATH)
        end

        carely_notification_error("google_api_token.ymlが不正です。") && return if credentials.nil?

        credentials
      end

      def aes_encrypt_token_file(file_path)
        yaml = YAML.load_file(file_path)
        token_info = yaml["default"]
        FileUtils.touch(file_path)
        store = YAML::Store.new(file_path)
        store.transaction do
          store["default"] = aes_encrypt(token_info)
        end
      end

      def aes_decrypt_token_file(file_path)
        yaml = YAML.load_file(file_path)
        token_info = yaml["default"]
        FileUtils.touch(file_path)
        store = YAML::Store.new(file_path)
        store.transaction do
          store["default"] = aes_decrypt(token_info)
        end
      end
    end
  end
end
