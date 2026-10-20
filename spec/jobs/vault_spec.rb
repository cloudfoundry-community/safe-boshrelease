require 'rspec'
require 'json'
require 'bosh/template/test'
require 'yaml'
require 'open3'
require 'tmpdir'
require 'fileutils'

describe 'vault' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../..')) }
  let(:job) { release.job('vault') }
  let(:template) { job.template('config/vault.config') }
  let(:properties) {{}}

  context 'config/vault.conf' do
    context 'with defaults' do
      it 'creates a default template' do
        rendered_template = template.render(properties)

        expect(rendered_template).to include('storage "consul" {')
        expect(rendered_template).to include('address = "127.0.0.1:8500"')
        expect(rendered_template).not_to include('backend "consul"')
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

  context 'bin/post-start' do
    let(:post_start) { job.template('bin/post-start') }
    let(:links) {
      [Bosh::Template::Test::Link.new(
        name: 'vault',
        instances: %w(10.0.0.1 10.0.0.2 10.0.0.3).map { |ip| Bosh::Template::Test::LinkInstance.new(address: ip) }
      )]
    }

    def render_post_start(props = {})
      post_start.render(props, consumes: links)
    end

    it 'is listed in the job spec and rendered to bin/post-start' do
      spec = YAML.load_file(File.join(File.dirname(__FILE__), '../../jobs/vault/spec'))
      expect(spec['templates']['bin/post-start']).to eq('bin/post-start')
    end

    context 'with defaults' do
      let(:rendered) { render_post_start }

      it 'expects one voter per linked vault instance' do
        expect(rendered).to include('EXPECTED_SERVERS=3')
      end

      it 'waits ten minutes, polling every five seconds' do
        expect(rendered).to include('GATE_TIMEOUT=600')
        expect(rendered).to include('GATE_INTERVAL=5')
      end

      it 'talks to Consul over HTTPS on 127.0.0.1 with the peer CA and client certificate' do
        expect(rendered).to include('export CONSUL_HTTP_ADDR=https://127.0.0.1:8500')
        expect(rendered).to include('export CONSUL_CACERT=${JOB_DIR}/tls/peer/ca.pem')
        expect(rendered).to include('export CONSUL_CLIENT_CERT=${JOB_DIR}/tls/peer/cert.pem')
        expect(rendered).to include('export CONSUL_CLIENT_KEY=${JOB_DIR}/tls/peer/key.pem')
        expect(rendered).not_to include('CONSUL_HTTP_SSL_VERIFY')
      end

      it 'uses the packaged consul binary and autopilot state' do
        expect(rendered).to include('CONSUL=/var/vcap/packages/consul/bin/consul')
        expect(rendered).to include('operator autopilot state')
        expect(rendered).to include('operator raft list-peers')
      end

      it 'is valid bash' do
        _out, err, status = Open3.capture3('bash', '-n', stdin_data: rendered)
        expect(status.success?).to be(true), err
      end
    end

    it 'follows the size of the vault link' do
      one = [Bosh::Template::Test::Link.new(
        name: 'vault',
        instances: [Bosh::Template::Test::LinkInstance.new(address: '10.0.0.1')]
      )]
      expect(post_start.render({}, consumes: one)).to include('EXPECTED_SERVERS=1')
    end

    it 'honours a custom timeout and interval' do
      rendered = render_post_start('safe' => { 'peer' => { 'post_start' => { 'timeout' => 1200, 'interval' => 10 } } })
      expect(rendered).to include('GATE_TIMEOUT=1200')
      expect(rendered).to include('GATE_INTERVAL=10')
    end

    [0, -5, 'ten', 1.5].each do |bad|
      it "rejects a timeout of #{bad.inspect}" do
        expect {
          render_post_start('safe' => { 'peer' => { 'post_start' => { 'timeout' => bad } } })
        }.to raise_error(/safe\.peer\.post_start\.timeout/)
      end
    end

    it 'rejects an interval longer than the timeout' do
      expect {
        render_post_start('safe' => { 'peer' => { 'post_start' => { 'timeout' => 10, 'interval' => 30 } } })
      }.to raise_error(/must not exceed/)
    end

    it 'omits the client certificate with self-signed peer certificates' do
      rendered = render_post_start('safe' => { 'peer' => { 'tls' => { 'verify' => false, 'use_self_signed_certs' => true } } })
      expect(rendered).not_to include('CONSUL_CLIENT_CERT')
      expect(rendered).not_to include('CONSUL_CLIENT_KEY')
      expect(rendered).to include('export CONSUL_HTTP_SSL_VERIFY=false')
    end

    context 'when run against a stubbed consul CLI' do
      let(:self_id) { '22222222-2222-2222-2222-222222222222' }
      let(:peers) { ['11111111-1111-1111-1111-111111111111', self_id, '33333333-3333-3333-3333-333333333333'] }

      def servers_with(&block)
        peers.each_with_index.map do |id, i|
          { id: id, status: i.zero? ? 'leader' : 'voter', healthy: true }.merge(block ? block.call(id) : {})
        end
      end

      # Mirrors the text layout of `consul operator autopilot state`.
      def autopilot(healthy: true, voters: peers, servers: servers_with)
        out = +''
        out << "Healthy:                      #{healthy}\n"
        out << "Failure Tolerance:            1\n"
        out << "Optimistic Failure Tolerance: 1\n"
        out << "Leader:                       #{peers.first}\n"
        out << "Voters:\n"
        voters.each { |id| out << "   #{id}\n" }
        out << "Servers:\n"
        servers.each_with_index do |s, i|
          out << "   #{s[:id]}\n"
          out << "      Name:            vault-#{i}\n"
          out << "      Address:         10.0.0.#{i + 1}:8300\n"
          out << "      Version:         2.0.4\n"
          out << "      Status:          #{s[:status]}\n"
          out << "      Node Type:       voter\n"
          out << "      Node Status:     alive\n"
          out << "      Healthy:         #{s[:healthy]}\n"
          out << "      Last Contact:    0s\n"
          out << "      Last Term:       3\n"
          out << "      Last Index:      120\n"
          out << "      Redundancy Zone: \n"
          out << "      Upgrade Version: \n"
          out << "      Read Replica:    false\n"
        end
        out
      end

      def info(last_log_index)
        "agent:\n\tcheck_monitors = 0\n\tserver = true\nraft:\n\tapplied_index = #{last_log_index}\n" \
          "\tlast_log_index = #{last_log_index}\n\tstate = Follower\nserf_lan:\n\tmembers = 1\n"
      end

      def members(alive)
        out = +"Node     Address          Status  Type    Build  Protocol  DC     Partition  Segment\n"
        3.times do |i|
          out << "vault-#{i}  10.0.0.#{i + 1}:8301  #{i < alive ? 'alive' : 'failed'}   server  2.0.4  2         vault  default    <all>\n"
        end
        out
      end

      # Serves autopilot_states one per call and repeats the last one; a nil
      # entry answers with the leaderless error that Consul returns.
      def run_gate(autopilot_states:, info_out: info(120), members_out: members(3), node_id: self_id, timeout: 3)
        Dir.mktmpdir do |dir|
          fake_bin = File.join(dir, 'bin')
          data_dir = File.join(dir, 'store')
          fixtures = File.join(dir, 'fixtures')
          FileUtils.mkdir_p([fake_bin, File.join(data_dir, 'consul'), fixtures])
          File.write(File.join(data_dir, 'consul', 'node-id'), node_id) if node_id

          autopilot_states.each_with_index do |state, i|
            File.write(File.join(fixtures, "autopilot.#{i + 1}"), state) unless state.nil?
          end
          File.write(File.join(fixtures, 'autopilot.count'), autopilot_states.size.to_s)
          File.write(File.join(fixtures, 'info'), info_out)
          File.write(File.join(fixtures, 'members'), members_out)

          File.write(File.join(fake_bin, 'timeout'), "#!/bin/bash\nshift\nexec \"$@\"\n")
          File.write(File.join(fake_bin, 'consul'), <<~SH)
            #!/bin/bash
            F=#{fixtures}
            case "$1 ${2:-}" in
              "operator autopilot")
                n=$(( $(cat $F/calls 2>/dev/null || echo 0) + 1 ))
                echo $n > $F/calls
                max=$(cat $F/autopilot.count)
                (( n > max )) && n=$max
                if [[ -f $F/autopilot.$n ]]; then cat $F/autopilot.$n; exit 0; fi
                echo "Error querying Autopilot state: Unexpected response code: 500 (No cluster leader)"
                exit 1
                ;;
              "operator raft") echo "Node  ID  Address  State  Voter  RaftProtocol  Commit Index  Trails Leader By" ;;
              "info "*)    cat $F/info ;;
              "members "*) cat $F/members ;;
              *) echo "unexpected consul call: $*"; exit 2 ;;
            esac
          SH
          FileUtils.chmod(0755, [File.join(fake_bin, 'timeout'), File.join(fake_bin, 'consul')])

          script = render_post_start('safe' => { 'peer' => { 'post_start' => { 'timeout' => timeout, 'interval' => 1 } } })
            .sub('CONSUL=/var/vcap/packages/consul/bin/consul', "CONSUL=#{fake_bin}/consul")
            .sub('DAT_DIR=/var/vcap/store/vault', "DAT_DIR=#{data_dir}")
          File.write(File.join(dir, 'post-start'), script)

          out, status = Open3.capture2e({ 'PATH' => "#{fake_bin}:#{ENV['PATH']}" }, 'bash', File.join(dir, 'post-start'))
          [out, status.exitstatus]
        end
      end

      it 'passes a healthy cluster where this server is a voter' do
        out, code = run_gate(autopilot_states: [autopilot])
        expect(code).to eq(0), out
        expect(out).to include('Consul raft gate passed: leader present, 3/3 voters')
      end

      it 'keeps waiting while autopilot holds this server as a non-voter' do
        staging = autopilot(
          voters: peers - [self_id],
          servers: servers_with { |id| id == self_id ? { status: 'non-voter' } : {} }
        )
        out, code = run_gate(autopilot_states: [staging, staging, autopilot], timeout: 8)
        expect(code).to eq(0), out
        expect(out).to include("is not a voter yet, status 'non-voter'")
        expect(out).to include('Consul raft gate passed')
      end

      it 'fails when the voter count is short of the instance count' do
        out, code = run_gate(autopilot_states: [autopilot(voters: peers.first(2))], timeout: 2)
        expect(code).to eq(1), out
        expect(out).to include('raft has 2 voters, expected 3')
        expect(out).to include('Consul raft gate FAILED')
      end

      it 'fails when this server is not in the raft configuration' do
        out, code = run_gate(autopilot_states: [autopilot], node_id: '44444444-4444-4444-4444-444444444444', timeout: 2)
        expect(code).to eq(1), out
        expect(out).to include("is not a voter yet, status 'absent'")
      end

      it 'fails when this server is an unhealthy voter' do
        sick = autopilot(servers: servers_with { |id| id == self_id ? { healthy: false } : {} })
        out, code = run_gate(autopilot_states: [sick], timeout: 2)
        expect(code).to eq(1), out
        expect(out).to include('is a voter but autopilot reports it unhealthy')
      end

      it 'fails when another server is unhealthy' do
        out, code = run_gate(autopilot_states: [autopilot(healthy: false)], timeout: 2)
        expect(code).to eq(1), out
        expect(out).to include('autopilot reports the cluster unhealthy')
      end

      it 'restarts the pass count when a poll fails' do
        out, code = run_gate(autopilot_states: [autopilot, autopilot, nil, autopilot], timeout: 10)
        expect(code).to eq(0), out
        expect(out).to include("local raft last_log_index is '120'")
        expect(out.scan(/post-start: pass: /).size).to eq(2)
      end

      it 'fails with no leader when this server holds raft data' do
        out, code = run_gate(autopilot_states: [nil], info_out: info(42), members_out: members(1), timeout: 2)
        expect(code).to eq(1), out
        expect(out).to include("local raft last_log_index is '42'")
      end

      it 'passes a new cluster still waiting for bootstrap_expect peers' do
        out, code = run_gate(autopilot_states: [nil], info_out: info(0), members_out: members(1))
        expect(code).to eq(0), out
        expect(out).to include('Consul raft gate passed for bootstrap: new cluster, 1/3 servers alive')
      end

      it 'waits for the election when every server of a new cluster is alive' do
        out, code = run_gate(autopilot_states: [nil], info_out: info(0), members_out: members(3), timeout: 2)
        expect(code).to eq(1), out
        expect(out).to include('waiting for the bootstrap election')
      end

      it 'fails when the agent has not written a node ID' do
        out, code = run_gate(autopilot_states: [autopilot], node_id: nil, timeout: 2)
        expect(code).to eq(1), out
        expect(out).to include('no node ID')
      end
    end
  end
end