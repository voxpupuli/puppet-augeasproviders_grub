require 'spec_helper_acceptance'

test_name 'Augeasproviders Grub'

describe 'Grub Tests' do
  tests = {
    :basic => {
      :manifest => %(
        kernel_parameter { 'audit':
          value    => '1'
        }),
      :test => %(grep "audit=1" /proc/cmdline)
    },
    :normal_bootmode => {
      :manifest => %(
        kernel_parameter { 'audit':
          value    => '1',
          bootmode => 'normal'
        }),
      :test => %(grep "audit=1" /proc/cmdline)
    }
  }

  tests.keys.each do |key|
    let(:manifest){ tests[key][:manifest] }
    let(:test){ tests[key][:test] }

    context "default parameters for #{key}" do
      hosts.each do |host|
        # Using puppet_apply as a helper
        it 'should work with no errors' do
          apply_manifest_on(host, manifest, :catch_failures => true)
        end
    
        it 'should be idempotent' do
          apply_manifest_on(host, manifest, {:catch_changes => true})
        end
    
        it 'is expected to have auditing enabled at boot time' do
          host.reboot
          on(host, test)
        end
      end
    end
  end
end
