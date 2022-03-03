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
      end
    end
  end
end