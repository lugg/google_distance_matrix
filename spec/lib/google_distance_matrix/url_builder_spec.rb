# frozen_string_literal: true

require 'spec_helper'

describe GoogleDistanceMatrix::UrlBuilder do
  let(:delimiter) { described_class::DELIMITER }
  let(:comma) { CGI.escape ',' }
  let(:colon) { CGI.escape ':' }

  let(:origin_1) { GoogleDistanceMatrix::Place.new address: 'address_origin_1' }
  let(:origin_2) { GoogleDistanceMatrix::Place.new address: 'address_origin_2' }

  let(:destination_1) { GoogleDistanceMatrix::Place.new lat: 1, lng: 11 }
  let(:destination_2) { GoogleDistanceMatrix::Place.new lat: 2, lng: 22 }

  let(:origins) { [origin_1, origin_2] }
  let(:destinations) { [destination_1, destination_2] }

  let(:config) { GoogleDistanceMatrix::Configuration.new }

  let(:matrix) do
    GoogleDistanceMatrix::Matrix.new(
      origins: origins,
      destinations: destinations,
      configuration: config
    )
  end

  subject { described_class.new matrix }

  describe '#initialize' do
    it 'has a matrix' do
      expect(described_class.new(matrix).matrix).to eq matrix
    end

    it 'fails if matrix is invalid' do
      expect do
        described_class.new GoogleDistanceMatrix::Matrix.new
      end.to raise_error GoogleDistanceMatrix::InvalidMatrix
    end

    it "fails if matrix's configuration is invalid" do
      expect do
        matrix.configure { |c| c.mode = 'foobar' }
        described_class.new matrix
      end.to raise_error GoogleDistanceMatrix::InvalidMatrix
    end
  end

  describe '#sensitive_url' do
    it 'fails if the url is more than 2048 characters' do
      long_string = +''
      2049.times { long_string << 'a' }

      expect(subject).to receive(:query_params_string).and_return long_string

      expect { subject.sensitive_url }.to raise_error GoogleDistanceMatrix::MatrixUrlTooLong
    end

    it 'starts with the base URL' do
      expect(subject.sensitive_url).to start_with 'https://' + described_class::BASE_URL
    end

    it 'has a configurable protocol' do
      matrix.configure { |c| c.protocol = 'http' }
      expect(subject.sensitive_url).to start_with 'http://'
    end

    it 'includes origins' do
      expect(subject.sensitive_url)
        .to include "origins=address_origin_1#{delimiter}address_origin_2"
    end

    it 'includes destinations' do
      expect(subject.sensitive_url).to include "destinations=1#{comma}11#{delimiter}2#{comma}22"
    end

    describe 'lat lng scale' do
      let(:destination_1) { GoogleDistanceMatrix::Place.new lat: 10.123456789, lng: '10.987654321' }

      it 'rounds lat and lng' do
        subject.matrix.configure { |c| c.lat_lng_scale = 5 }

        expect(subject.sensitive_url).to include "destinations=10.12346#{comma}10.98765"
      end
    end

    describe 'use encoded polylines' do
      let(:destination_3) { GoogleDistanceMatrix::Place.new address: 'address_destination_3' }
      let(:destination_4) { GoogleDistanceMatrix::Place.new lat: 4, lng: 44 }
      let(:destinations) { [destination_1, destination_2, destination_3, destination_4] }

      before do
        matrix.configure { |c| c.use_encoded_polylines = true }
      end

      it 'includes places with addresses as addresses' do
        expect(subject.sensitive_url)
          .to include "origins=address_origin_1#{delimiter}address_origin_2"
      end

      it(
        'encodes places with lat/lng values togheter, broken up by addresses to keep places order'
      ) do
        expect(subject.sensitive_url).to include(
          # 2 first places encoded togheter as they have lat lng values
          "destinations=enc#{colon}_ibE_mcbA_ibE_mcbA#{colon}#{delimiter}" +
          # encoded polyline broken off by a destination with address
          "address_destination_3#{delimiter}" +
          # We continue to encode the last destination as it's own ony point polyline
          "enc#{colon}_glW_wpkG#{colon}"
        )
      end
    end

    describe 'configuration' do
      context 'with google api key set' do
        before do
          matrix.configure do |config|
            config.google_api_key = '12345'
          end
        end

        it 'includes the api key' do
          expect(subject.sensitive_url).to include "key=#{matrix.configuration.google_api_key}"
        end
      end

      context 'with google business client id and private key set' do
        before do
          matrix.configure do |config|
            config.google_business_api_client_id = '123'
            config.google_business_api_private_key = 'c2VjcmV0'
          end
        end

        it 'includes client' do
          expect(subject.sensitive_url)
            .to include "client=#{matrix.configuration.google_business_api_client_id}"
        end

        it 'has signature' do
          expect(subject.sensitive_url).to include 'signature=DIUgkQ_BaVBJU6hwhzH3GLeMdeo='
        end
      end
    end
  end

  describe '#filtered_url' do
    it 'filters nothing if config has no keys to be filtered' do
      config.filter_parameters_in_logged_url.clear

      expect(subject)
        .to receive(:sensitive_url)
        .and_return 'https://example.com/?foo=bar&sensitive=secret'

      expect(subject.filtered_url).to eq 'https://example.com/?foo=bar&sensitive=secret'
    end

    it 'filters sensitive GET param if config has it in list of params to filter' do
      config.filter_parameters_in_logged_url << 'sensitive'

      expect(subject)
        .to receive(:sensitive_url)
        .and_return 'https://example.com/?foo=bar&sensitive=secret'

      expect(subject.filtered_url).to eq 'https://example.com/?foo=bar&sensitive=[FILTERED]'
    end

    it 'filters key and signature as defaul from configuration' do
      expect(subject)
        .to receive(:sensitive_url)
        .and_return 'https://example.com/?key=bar&signature=secret&other=foo'

      expect(subject.filtered_url)
        .to eq 'https://example.com/?key=[FILTERED]&signature=[FILTERED]&other=foo'
    end

    it 'filters all appearances of a param' do
      expect(subject)
        .to receive(:sensitive_url)
        .and_return 'https://example.com/?key=bar&key=secret&other=foo'

      expect(subject.filtered_url)
        .to eq 'https://example.com/?key=[FILTERED]&key=[FILTERED]&other=foo'
    end
  end
end
