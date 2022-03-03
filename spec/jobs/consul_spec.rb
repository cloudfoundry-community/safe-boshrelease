require 'rspec'
require 'json'
require 'bosh/template/test'
require 'yaml'

describe 'consul' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../..')) }
  let(:job) { release.job('vault') }
  let(:template) { job.template('config/consul.json') }
  let(:properties) {{}}
  let(:links) {
    [Bosh::Template::Test::Link.new(
      name: 'vault',
      instances: [Bosh::Template::Test::LinkInstance.new(address: 'vault.address')]
    )]
  }

  context 'config/consul.conf' do
    context 'with self signed certificates' do
      it 'creates a default template' do
        properties.merge!({
          'safe' => { 
            'peer' => { 
              'tls' => { 
                'verify' => false
              }
            }
          }
        })
        rendered_template = JSON.parse(template.render(properties, consumes: links))

        expect(rendered_template['datacenter']).to eq('vault')
        # expect(rendered_template).to include('tls_cert_file   = "/var/vcap/jobs/consul/tls/peer/cert.pem"')
        # expect(rendered_template).to include('tls_key_file    = "/var/vcap/jobs/consul/tls/peer/key.pem"')
        # expect(rendered_template).to include('address = "0.0.0.0:443"')
        # expect(rendered_template).to include('ui = false')
        # expect(rendered_template).to include('api_addr = "https://192.168.0.0:443"')
      end
    end

    # context 'with tls settings' do
    #   context 'safe.peer.tls.verify = false' do
    #     it 'skips ssl verification' do
    #       properties.merge!({
    #         'safe' => { 
    #           'peer' => { 
    #             'tls' => { 
    #               'verify' => false
    #             }
    #           }
    #         }
    #       })
    #       rendered_template = template.render(properties)

    #       expect(rendered_template).to include('tls_skip_verify = "true"')
    #     end
    #   end

    #   context 'safe.peer.tls.self_signed = true' do
    #     it 'does not include cert and key files' do
    #       properties.merge!({
    #         'safe' => { 
    #           'peer' => { 
    #             'tls' => { 
    #               'self_signed' => true
    #             }
    #           }
    #         }
    #       })
    #       rendered_template = template.render(properties)

    #       expect(rendered_template).not_to include('tls_cert_file   = "/var/vcap/jobs/consul/tls/peer/cert.pem"')
    #       expect(rendered_template).not_to include('tls_key_file    = "/var/vcap/jobs/consul/tls/peer/key.pem"')
    #     end
    #   end
    # end
  end
end