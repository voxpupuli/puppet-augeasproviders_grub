require 'spec_helper_acceptance'

test_name 'Augeasproviders Grub'

describe 'Global Config Tests' do
  hosts.each do |host|
    if fact_on(host,'osfamily') == 'RedHat'
      if fact_on(host,'operatingsystemmajrelease').to_s <= '6'
        context 'set timeout in grub' do
          let(:manifest) { %(
            grub_config { 'timeout':
              value    => '1'
            }
          )}

          # Using puppet_apply as a helper
          it 'should work with no errors' do
            apply_manifest_on(host, manifest, :catch_failures => true)
          end

          it 'should be idempotent' do
            apply_manifest_on(host, manifest, {:catch_changes => true})
          end

          it 'should have a timeout of 1' do
            on(host, %(grep "timeout=1" /etc/grub.conf))
          end
        end

        context 'set invalid variable in grub' do
          let(:manifest) { %(
            grub_config { 'foobar': }
          )}

          # Using puppet_apply as a helper
          it 'should fail to apply' do
            result = apply_manifest_on(host, manifest, :expect_failures => true)
            expect(result.output).to match(/Grub_config\[foobar\].*Failed to save Augeas tree/)
          end
        end

        context 'set fallback in grub' do
          let(:manifest) { %(
            grub_config { 'fallback':
              value    => '0'
            }
          )}

          it 'should work with no errors' do
            apply_manifest_on(host, manifest, :catch_failures => true)
          end

          it 'should be idempotent' do
            apply_manifest_on(host, manifest, {:catch_changes => true})
          end

          it 'should have a fallback of 0' do
            on(host, %(grep "fallback 0" /etc/grub.conf))
          end
        end
      else
        context 'set timeout in grub2' do
          let(:manifest) { %(
            grub_config { 'GRUB_TIMEOUT':
              value    => '1'
            }
          )}

          # Using puppet_apply as a helper
          it 'should work with no errors' do
            apply_manifest_on(host, manifest, :catch_failures => true)
          end

          it 'should be idempotent' do
            apply_manifest_on(host, manifest, {:catch_changes => true})
          end

          it 'should have a timeout of 1' do
            on(host, %(grep "GRUB_TIMEOUT=1" /etc/default/grub))
            on(host, %(grep "timeout=1" /boot/grub2/grub.cfg))
          end
        end

        context 'set arbitrary value in grub2' do
          let(:manifest) { %(
            grub_config { 'GRUB_FOOBAR':
              value    => 'BAZ'
            }
          )}

          # Using puppet_apply as a helper
          it 'should work with no errors' do
            apply_manifest_on(host, manifest, :catch_failures => true)
          end

          it 'should be idempotent' do
            apply_manifest_on(host, manifest, {:catch_changes => true})
          end

          it 'should have a GRUB_FOOBAR of BAZ' do
            on(host, %(grep "GRUB_FOOBAR=BAZ" /etc/default/grub))
          end
        end

        context 'remove value in grub2' do
          let(:manifest) { %(
            grub_config { 'GRUB_FOOBAR':
              ensure => 'absent'
            }
          )}

          # Using puppet_apply as a helper
          it 'should work with no errors' do
            apply_manifest_on(host, manifest, :catch_failures => true)
          end

          it 'should be idempotent' do
            apply_manifest_on(host, manifest, {:catch_changes => true})
          end

          it 'should not have a GRUB_FOOBAR' do
            on(host, %(grep "GRUB_FOOBAR" /etc/default/grub), :acceptable_exit_codes => [1])
          end
        end
      end
    end
  end
end
