# Copyright:: Copyright (c) 2013-2016 Megam Systems
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'base64'
require 'time'
require 'excon'
require 'uri'
require 'zlib'
require 'openssl'

__LIB_DIR__ = File.expand_path(File.join(File.dirname(__FILE__), '..'))
$LOAD_PATH.unshift(__LIB_DIR__) unless $LOAD_PATH.include?(__LIB_DIR__)

require 'megam/api/accounts'
require 'megam/api/assemblies'
require 'megam/api/assembly'
require 'megam/api/balances'
require 'megam/api/billedhistories'
require 'megam/api/billingtranscations'
require 'megam/api/components'
require 'megam/api/domains'
require 'megam/api/errors'
require 'megam/api/marketplaces'
require 'megam/api/organizations'
require 'megam/api/promos'
require 'megam/api/requests'
require 'megam/api/sensors'
require 'megam/api/sshkeys'
require 'megam/api/eventsvm'
require 'megam/api/eventscontainer'
require 'megam/api/eventsbilling'
require 'megam/api/eventsstorage'
require 'megam/api/snapshots'
require 'megam/api/version'

require 'megam/mixins/assemblies'
require 'megam/mixins/assembly'
require 'megam/mixins/common_deployable'
require 'megam/mixins/components'
require 'megam/mixins/megam_attributes'
require 'megam/mixins/outputs'
require 'megam/mixins/policies'

require 'megam/core/rest_adapter'
require 'megam/core/stuff'
require 'megam/core/text'
require 'megam/core/log'
require 'megam/core/json_compat'
require 'megam/core/error'
require 'megam/core/account'
require 'megam/core/request'
require 'megam/core/request_collection'
require 'megam/core/sshkey'
require 'megam/core/sshkey_collection'
require 'megam/core/eventsvm'
require 'megam/core/eventsvm_collection'
require 'megam/core/eventscontainer'
require 'megam/core/eventscontainer_collection'
require 'megam/core/eventsbilling'
require 'megam/core/eventsbilling_collection'
require 'megam/core/eventsstorage'
require 'megam/core/eventsstorage_collection'
require 'megam/core/marketplace'
require 'megam/core/marketplace_collection'
require 'megam/core/organizations'
require 'megam/core/organizations_collection'
require 'megam/core/domains'
require 'megam/core/domain_collection'
require 'megam/core/assemblies'
require 'megam/core/assemblies_collection'
require 'megam/core/konipai'
require 'megam/core/assembly'
require 'megam/core/assembly_collection'
require 'megam/core/components'
require 'megam/core/components_collection'
require 'megam/core/sensors'
require 'megam/core/sensors_collection'
require 'megam/core/snapshots'
require 'megam/core/snapshots_collection'
require 'megam/core/balances_collection'
require 'megam/core/balances'
require 'megam/core/billedhistories_collection'
require 'megam/core/billedhistories'
require 'megam/core/billingtranscations_collection'
require 'megam/core/billingtranscations'
require 'megam/core/promos'

module Megam
  class API

    # text is used to print stuff in the terminal (message, log, info, warn etc.)
    attr_accessor :text

    API_VERSION2 = '/v2'.freeze

    X_Megam_DATE = 'X-Megam-DATE'.freeze
    X_Megam_HMAC = 'X-Megam-HMAC'.freeze
    X_Megam_OTTAI = 'X-Megam-OTTAI'.freeze
    X_Megam_ORG  = 'X-Megam-ORG'.freeze
    X_Megam_PUTTUSAVI = 'X-Megam-PUTTUSAVI'.freeze

    HEADERS = {
      'Accept' => 'application/json',
      'Accept-Encoding' => 'gzip',
      'User-Agent' => "megam-api/#{Megam::API::VERSION}",
      'X-Ruby-Version' => RUBY_VERSION,
      'X-Ruby-Platform' => RUBY_PLATFORM
    }

    OPTIONS = {
      headers: {},
      host: '127.0.0.1',
      nonblock: false,
      scheme: 'http'
    }

    def text
      @text ||= Megam::Text.new(STDOUT, STDERR, STDIN, {})
    end

    attr_reader :last_response

    # It is assumed that every API call will use an API_KEY/email. This ensures validity of the person
    # really the same guy on who he claims.
    # 3 levels of options exits
    # 1. The global OPTIONS as available inside the API (OPTIONS)
    # 2. The options as passed via the instantiation of API will override global options. The ones that are passed are :email and :api_key and will
    # be  merged into a class variable @options
    # 3. Upon merge of the options, the api_key, email as available in the @options is deleted.
    def initialize(options = {})
      @options = OPTIONS.merge(options)
      @api_key = @options.delete(:api_key) || ENV['MEGAM_API_KEY']
      @email = @options.delete(:email)
      @password = @options.delete(:password)
      @org_id = @options.delete(:org_id)
      unless !@options.delete(:reset_flag)
         fail Megam::API::Errors::AuthKeysMissing if (@email.nil? && @api_key.nil?) || (@email.nil? && @password.nil?)
      end
    end

    def request(params, &block)

      just_color_debug("#{@options[:path]}")
      start = Time.now
      Megam::Log.debug('START')
      params.each do |pkey, pvalue|
        Megam::Log.debug("> #{pkey}: #{pvalue}")
      end

      begin
        response = connection.request(params, &block)
      rescue Excon::Errors::HTTPStatusError => error
        klass = case error.response.status

        when 401 then Megam::API::Errors::Unauthorized
        when 403 then Megam::API::Errors::Forbidden
        when 404 then Megam::API::Errors::NotFound
        when 408 then Megam::API::Errors::Timeout
        when 422 then Megam::API::Errors::RequestFailed
        when 423 then Megam::API::Errors::Locked
        when /50./ then Megam::API::Errors::RequestFailed
        else Megam::API::Errors::ErrorWithResponse
        end
        reerror = klass.new(error.message, error.response)
        reerror.set_backtrace(error.backtrace)
        Megam::Log.debug("#{reerror.response.body}")
        reerror.response.body = Megam::JSONCompat.from_json(reerror.response.body.chomp)
        Megam::Log.debug('RESPONSE ERR: Ruby Object')
        Megam::Log.debug("#{reerror.response.body}")
        raise(reerror)
      end

      @last_response = response
      Megam::Log.debug('RESPONSE: HTTP Status and Header Data')
      Megam::Log.debug("> HTTP #{response.remote_ip} #{response.status}")

      response.headers.each do |header, value|
        Megam::Log.debug("> #{header}: #{value}")
      end
      Megam::Log.debug('End HTTP Status/Header Data.')

      if response.body && !response.body.empty?
        if response.headers['Content-Encoding'] == 'gzip'
          Megam::Log.debug('RESPONSE: Content-Encoding is gzip')
          response.body = Zlib::GzipReader.new(StringIO.new(response.body)).read
        end
        Megam::Log.debug('RESPONSE: HTTP Body(JSON)')
        Megam::Log.debug("#{response.body}")

        begin
          unless response.headers[X_Megam_OTTAI]
            response.body = Megam::JSONCompat.from_json(response.body.chomp)
            Megam::Log.debug('RESPONSE: Ruby Object')
          else
            response.body = Megam::KoniPai.new.koni(response.body.chomp)
            Megam::Log.debug('RESPONSE: KoniPai Object ')
          end
          Megam::Log.debug("#{response.body}")
        rescue Exception => jsonerr
          Megam::Log.error(jsonerr)
          raise(jsonerr)
        end
      end
      Megam::Log.debug("END(#{(Time.now - start)}s)")
      # reset (non-persistent) connection
      @connection.reset
      response
    end

    private

    def just_color_debug(path)
      text.msg "--> #{text.color("(#{path})", :cyan, :bold)}"                  # Why " inside "
    end

    # Make a lazy connection.
    def connection
      @options[:path] = API_VERSION2 + @options[:path]
      encoded_api_header = encode_header(@options)
      @options[:headers] = HEADERS.merge(X_Megam_HMAC => encoded_api_header[:hmac],
      X_Megam_DATE => encoded_api_header[:date], X_Megam_ORG => "#{@org_id}").merge(@options[:headers])
      if (@api_key == "" || @api_key.nil?)
         @options[:headers] = @options[:headers].merge(X_Megam_PUTTUSAVI => "true") unless (@password == "" || @password.nil?)
      end

      Megam::Log.debug('HTTP Request Data:')
      Megam::Log.debug("> HTTP #{@options[:scheme]}://#{@options[:host]}")
      @options.each do |key, value|
        Megam::Log.debug("> #{key}: #{value}")
      end
      Megam::Log.debug('End HTTP Request Data.')
      if @options[:scheme] == 'https'
        @connection = Excon.new("#{@options[:scheme]}://#{@options[:host]}", @options)
      else
        Excon.defaults[:ssl_verify_peer] = false
        @connection = Excon.new("#{@options[:scheme]}://#{@options[:host]}:9000", @options)
      end
      @connection
    end

    ## encode header as per rules.
    # The input hash will have
    # :api_key, :email, :body, :path
    # The output will have
    # :hmac
    # :date
    def encode_header(cmd_parms)
      header_params = {}
      body_digest = OpenSSL::Digest::MD5.digest(cmd_parms[:body])
      body_base64 = Base64.encode64(body_digest)

      current_date = Time.now.strftime('%Y-%m-%d %H:%M')

      data = "#{current_date}" + "\n" + "#{cmd_parms[:path]}" + "\n" + "#{body_base64}"

      digest  = OpenSSL::Digest.new('sha1')
      movingFactor = data.rstrip!
      if !(@password.nil?) && @api_key.nil?
        hash = OpenSSL::HMAC.hexdigest(digest, Base64.strict_decode64(@password), movingFactor)
      elsif !(@api_key.nil?)
        hash = OpenSSL::HMAC.hexdigest(digest, @api_key, movingFactor)
      else
        hash = OpenSSL::HMAC.hexdigest(digest, "", movingFactor)
      end
      final_hmac = @email + ':' + hash
      header_params = { hmac: final_hmac, date: current_date }
    end
  end
end
