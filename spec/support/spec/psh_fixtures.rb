# frozen_string_literal: true

def fixtures(*rest)
  File.join('spec', 'fixtures', *rest)
end

# Returns the path to your relative fixture dir. So if your spec test is
# <project>/spec/unit/facter/foo_spec.rb then your relative dir will be
# <project>/spec/fixture/unit/facter/foo
def my_fixture_dir
  callers = caller
  while (line = callers.shift)
    next unless (found = line.match(%r{/spec/(.*)_spec\.rb:}))

    return fixtures(found[1])
  end
  raise "sorry, I couldn't work out your path from the caller stack!"
end

# Given a name, returns the full path of a file from your relative fixture
# dir as returned by my_fixture_dir.
def my_fixture(name)
  file = File.join(my_fixture_dir, name)
  raise "fixture '#{name}' for #{my_fixture_dir} is not readable" unless File.readable? file

  file
end
