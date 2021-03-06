# gem
require "bundler/setup"
require "graphql/client"
require "graphql/client/http"

require "./app/carely/api_client"
require "./app/common/common_process"

include App::Common::CommonProcess

module App
  module Graphql
    module GraphqlQuery

      # Carely APIを使うための準備
      carely_api_client = App::Carely::ApiClient.new
      # Carely APIのtokenの疎通確認
      carely_api_client.verification_token_and_refresh

      token_yaml_data = YAML.load_file(App::Carely::ApiClient::CARELY_API_TOKEN_FILE_PATH)
      carely_api_access_token = aes_decrypt(token_yaml_data["token"])

      HTTP = GraphQL::Client::HTTP.new(App::Carely::ApiClient::CARELY_API_ENDPOINT) do
        define_method :headers do |_context|
          { 'Authorization' => "Bearer #{carely_api_access_token}" }
        end
      end

      # GraphQL::Client.load_schema(HTTP) の処理で下記のエラーが出ることがあるので処理を追加している
      # "Failed to open TCP connection to [HOST NAME] (getaddrinfo: System error)"
      retry_count = 0
      begin
        Schema = GraphQL::Client.load_schema(HTTP)
        Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
      rescue SocketError => e
        if retry_count <= 5
          sleep 3
          retry_count += 1
          puts "GraphqlQuery retry:#{retry_count}"
          retry
        else
          raise e
        end
      end

      CustomerQuery = Client.parse <<~GRAPHQL
        query($first: Int, $after: String, $branch_names: [String!], $employee_numbers: [String!], $emails: [String!], $names: [String!]) {
          customers(first: $first, after: $after, branchNames: $branch_names, employeeNumbers: $employee_numbers, emails: $emails, names: $names) {
            pageInfo {
              hasPreviousPage
              hasNextPage
              endCursor
              startCursor
            }
            edges {
              cursor
              node {
                age
                bio
                bornOn
                branch {
                  displayName
                  uuid
                }
                department {
                  customersCount
                  displayName
                  uuid
                }
                email
                employeeNumber
                employmentStatus
                employmentStatusText
                errors
                fullname
                fullnameJa
                gender
                genderText
                groupAnalysis {
                  displayName
                  uuid
                }
                hasStressCheck
                hasStressCheckText
                jobTitle
                joinOn
                profilePicturePath
                uuid
                workingArrangement
                workplace {
                  customersCount
                  name
                  uuid
                }
              }
            }
          }
        }
      GRAPHQL

    end
  end
end
