# carely-api-client-for-lambda-ruby

## 説明
Carely APIを使ってスプレッドシートのデータをCarelyへ登録、更新するためのサンプルプログラムです。  
AWS Lambda上で動作する前提で作成してあります。  
プログラム内で使用しているスプレッドシートのフォーマットは[こちら](https://docs.google.com/spreadsheets/d/11HwYLKa38IuSA0XRHJb6yzDIcgBKX8TrnpVbTkWJ_fQ/edit#gid=0) です。

## フロー
iCARE社内でも実際に使っているのですが従業員の入社、退職などがあればスプレッドシートを更新(入社であれば1行追加、退職であれば該当従業員の就業ステータスを退職へ変更など)して
SlackよりLambdaを起動してCarely APIを実行しています。以下のようなフローで実行させています。  

1. Slack Appへメンション  
1. AWS API Gateway経由でlambdaをcall  
1. lambda関数でGoogleSpreadSheetを読み込み、Carely APIを使用して従業員情報のチェック or 更新、登録をおこなう  
1. Slackのchannelへ結果を通知  

## スタートアップガイド
slack, API Gateway, lambdaの連携のサンプルは[こちらの記事](https://qiita.com/nobuo_hirai/items/008fbf643726614d4a8e) を参考にして下さい。


### 開発環境セットアップ
#### rubyのinstall
ruby 2.5.8をインストールして下さい。

#### git clone & bundle install
```
git clone git@github.com:icare-jp-oss/carely-api-client-for-lambda-ruby.git
```

```
# lambdaへvendor/bundleも配置する必要があるのでapplication内へinstallしてください
bundle config set --local path 'vendor/bundle'
bundle install
```

#### `credentials`と`token`の設定方法  
```
carely-api-client-for-lambda-ruby/
                         └ config/
                                ┣ carely_api_token.yml(local用確認用)
                                ┣ credentials.json(local用確認用)
                                ┣ google_api_token.json(local用確認用)
                                └ spreadsheet_info.json(localとlambda用)

```
credentials.jsonは[こちら](https://developers.google.com/sheets/api/quickstart/ruby) のSTEP1でダウンロードした`credentials.json`です。  


#### ローカルでのCarely API接続先
ローカルで実行する場合はCarely APIの接続先はdemo環境になります。  


## ローカルでの実行方法
```
bundle exec ruby lambda_function.rb
```

## lambdaへdeploy

### zip file作成
```
zip -r carely-api-client-for-lambda-ruby.zip vendor app config lambda_function.rb
```

### s3へzip fileをupload
```
aws s3 cp carely-api-client-for-lambda-ruby.zip s3://[bucket名]/[ディレクトリ名]/
```

### S3からlambdaへアップロードする時のURL
```
s3://[bucket名]/[ディレクトリ名]/carely-api-client-for-lambda-ruby.zip
```


#### lambdaの環境変数
lambdaの環境変数へセットする内容  

| key | value |
| ---- | ---- |
| api_app_id | Slackのapi_app_id (SlackのAppページに表示されているApp ID) |
| bucket_name | S3のファイル保存用bucket名 |
| channel_id | 呼び出し元のSlack channel id。対象のchannel以外は実行を許可しない(channel idの確認方法は該当のchannelをアプリで選択して、右クリックでリンクをコピーします。それをブラウザへ貼り付け、/archives/以降がidです。) |
| execution | 文字列でlambdaと入力 (localから実行されたかlambdaから実行されたかを判定) |
| google_api_credential | googleのcredentials.jsonの内容 |
| google_api_token | googleのapi token情報 |
| notification_slack_channel | slackの通知先channel名(#hogehogeのように入力) |
| password | S3へファイルを暗号化して保存するときに使用するpassword |
| s3_directory | S3のファイル保存用ディレクトリ名 |
| salt | S3へファイルを暗号化して保存するときに使用するsalt |
| slack_token | Slackのaccess token(Bot User OAuth Access Token) |

## お問い合わせ
本プログラムについてのお問い合わせは `dev+api@icare.jpn.com` へご連絡ください。

### ライセンス
[MIT](https://github.com/icare-jp-oss/carely-api-client-for-lambda-ruby/blob/master/LICENSE)
