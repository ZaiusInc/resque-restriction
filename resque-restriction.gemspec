# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run the gemspec command
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{resque-restriction}
  s.version = "0.2.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Richard Huang"]
  s.date = %q{2010-09-09}
  s.description = %q{resque-restriction is an extension to resque queue system that restricts the execution number of certain jobs in a period time, the exceeded jobs will be executed at the next period.}
  s.email = %q{flyerhzm@gmail.com}
  s.extra_rdoc_files = [
    "LICENSE",
     "README.markdown"
  ]
  s.files = [
    ".gitignore",
     "LICENSE",
     "README.markdown",
     "Rakefile",
     "VERSION",
     "init.rb",
     "lib/resque-restriction.rb",
     "lib/resque-restriction/job.rb",
     "lib/resque-restriction/restriction_job.rb",
     "rails/init.rb",
     "resque-restriction.gemspec",
     "spec/redis-test.conf",
     "spec/resque-restriction/job_spec.rb",
     "spec/resque-restriction/restriction_job_spec.rb",
     "spec/spec.opts",
     "spec/spec_helper.rb"
  ]
  s.homepage = %q{http://github.com/flyerhzm/resque-restriction}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.6}
  s.summary = %q{resque-restriction is an extension to resque queue system that restricts the execution number of certain jobs in a period time.}
  s.test_files = [
    "spec/resque-restriction/job_spec.rb",
     "spec/resque-restriction/restriction_job_spec.rb",
     "spec/spec_helper.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<resque>, [">= 1.7.0"])
    else
      s.add_dependency(%q<resque>, [">= 1.7.0"])
    end
  else
    s.add_dependency(%q<resque>, [">= 1.7.0"])
  end
end

