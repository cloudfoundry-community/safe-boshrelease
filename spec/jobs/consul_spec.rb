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
        expect(rendered_template['retry_join']).to eq(['vault.address'])
        expect(rendered_template).not_to have_key('start_join')
        expect(rendered_template).not_to have_key('ca_file')
        expect(rendered_template['tls']['defaults']['verify_outgoing']).to eq(false)
        expect(rendered_template['tls']['defaults']['cert_file']).to eq('/var/vcap/jobs/vault/tls/peer/cert.pem')
      end

      it 'keeps a stopping server in raft on SIGINT and SIGTERM' do
        properties.merge!({ 'safe' => { 'peer' => { 'tls' => { 'verify' => false } } } })
        rendered_template = JSON.parse(template.render(properties, consumes: links))

        expect(rendered_template['leave_on_terminate']).to eq(false)
        expect(rendered_template['skip_leave_on_interrupt']).to eq(true)
      end
    end
  end
end