require 'rspec'
require 'json'
require 'bosh/template/test'
require 'yaml'

describe 'vault' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../..')) }
  let(:job) { release.job('vault') }
  let(:template) { job.template('config/vault.config') }
  let(:properties) {{}}

  context 'config/vault.conf' do
    context 'with defaults' do
      it 'creates a default template' do
        rendered_template = template.render(properties)

        expect(rendered_template).to include('tls_skip_verify = "false"')
        expect(rendered_template).to include('tls_cert_file   = "/var/vcap/jobs/vault/tls/peer/cert.pem"')
        expect(rendered_template).to include('tls_key_file    = "/var/vcap/jobs/vault/tls/peer/key.pem"')
        expect(rendered_template).to include('address = "0.0.0.0:443"')
        expect(rendered_template).to include('ui = false')
        expect(rendered_template).to include('api_addr = "https://192.168.0.0:443"')
      end
    end

    context 'with tls settings' do
      context 'safe.peer.tls.verify = false' do
        it 'skips ssl verification' do
          properties.merge!({
            'safe' => { 
              'peer' => { 
                'tls' => { 
                  'verify' => false
                }
              }
            }
          })
          rendered_template = template.render(properties)

          expect(rendered_template).to include('tls_skip_verify = "true"')
        end
      end

      context 'safe.peer.tls.use_self_signed_certs = true' do
        it 'does not include cert and key files' do
          properties.merge!({
            'safe' => { 
              'peer' => { 
                'tls' => { 
                  'use_self_signed_certs' => true
                }
              }
            }
          })
          rendered_template = template.render(properties)

          expect(rendered_template).not_to include('tls_cert_file   = "/var/vcap/jobs/vault/tls/peer/cert.pem"')
          expect(rendered_template).not_to include('tls_key_file    = "/var/vcap/jobs/vault/tls/peer/key.pem"')
        end
      end
    end
  end
end