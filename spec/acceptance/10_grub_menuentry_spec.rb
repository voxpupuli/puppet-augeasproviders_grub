# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name 'Augeasproviders Grub'

describe 'GRUB Menuentry Tests' do
  hosts.each do |host|
    context "on #{host}" do
      context 'set new default kernel' do
        let(:manifest) do
          %(
          grub_menuentry { 'Standard':
            default_entry  => true,
            root           => '(hd0,msdos1)',
            kernel         => ':preserve:',
            initrd         => ':preserve:',
            kernel_options => [':preserve:', 'trogdor=BURNINATE']
          }
          )
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'has set the default to the new entry' do
          os_family = fact_on(host, 'os.family')

          if os_family == 'Debian'
            # On Debian, check /boot/grub/grub.cfg for the default entry
            grub_cfg = on(host, %(cat /boot/grub/grub.cfg)).stdout

            # Find the menuentry blocks
            menuentry_section = grub_cfg.scan(%r{menuentry '([^']+)'[^{]*{([^}]+)}}m)

            # Get the default entry number from GRUB_DEFAULT
            default_line = on(host, %(grep '^GRUB_DEFAULT=' /etc/default/grub || echo 'GRUB_DEFAULT=0')).stdout.strip
            default_value = default_line.split('=').last.strip.delete('"\'')

            # If default is a number, get that menuentry; if it's a name, find it
            if default_value =~ %r{^\d+$}
              default_idx = default_value.to_i
              expect(menuentry_section[default_idx]).not_to be_nil
              default_entry = menuentry_section[default_idx]
            else
              default_entry = menuentry_section.find { |title, _| title == default_value || title.include?('Standard') }
            end

            expect(default_entry).not_to be_nil
            expect(default_entry[1]).to include('trogdor=BURNINATE')
          else
            # Red Hat-based systems use grubby
            result = on(host, %(grubby --info=DEFAULT)).stdout
            result_hash = {}
            result.each_line do |line|
              line =~ %r{^\s*(.*?)=(.*)\s*$}
              result_hash[Regexp.last_match(1).strip] = Regexp.last_match(2).strip
            end

            expect(result_hash['title'].delete('"')).to eq('Standard')
            expect(result_hash['args'].delete('"')).to include('trogdor=BURNINATE')
          end
        end

        it 'activates on reboot' do
          host.reboot

          result = on(host, %(cat /proc/cmdline)).stdout
          expect(result.split(%r{\s+})).to include('trogdor=BURNINATE')
        end
      end
    end
  end
end
