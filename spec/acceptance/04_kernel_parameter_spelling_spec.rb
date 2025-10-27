# frozen_string_literal: true

# CATCHES Error: /Stage[main]/Main/Kernel_parameter[ipv6_disable_all]: Could not evaluate: incompatible encoding regexp match (Windows-31J regexp with UTF-8 string
# CATCHES removes an entry with another name than namevar

require 'spec_helper_acceptance'

test_name 'Augeasproviders Grub'

before_manifest=%(
  kernel_parameter { 'ipv6_disable_all_spelling1':
    name => "ipv6.disable",
    ensure => present,
    bootmode => 'all',
  }
  kernel_parameter { 'ipv6_disable_all_spelling2':
    name => "ipv6_disable",
    ensure => present,
    bootmode => 'all',
  }
  kernel_parameter { 'ipv6_disable_all_spelling3':
    name => "ipv6ödisable",
    ensure => present,
    bootmode => 'all',
  }
)


describe 'Kernel Parameter Tests' do
  tests = {
    misspelled_three_times: {
      manifest: %(
        kernel_parameter { 'ipv6_disable_all':
          name => "ipv6.disable",
          ensure => absent,
          bootmode => 'all',
        })
      test: %(test $(grep -o disable /etc/default/grub   |wc -l ) -eq 2)
    },
  }

  tests.each do |name, params|
    context "default parameters for #{name}" do
      let(:manifest) { params[:manifest] }
      let(:test) { params[:test] }

      hosts.each do |host|
        before(:context) do
          apply_manifest_on(host, before_manifest)
        end
        context "on #{host}" do
          # Using puppet_apply as a helper
          it 'works with without encoding errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, catch_changes: true)
          end

          it 'is removes only one of three entries' do
            on(host, test)
          end
        end
      end
    end
  end
end
