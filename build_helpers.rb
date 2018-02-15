require 'pathname'

def findSourceFiles(directories, extensions)
    sources = []
    extensions.each do |extension|
        directories.each do |directory|
            dir = Pathname(directory).cleanpath.to_s
            Dir::glob(File.join("#{dir}", "**", "*#{extension}")).each do |filename|
                sources.push(Pathname(filename).cleanpath.to_s)
            end
        end
    end
    return sources
end

def scanSourceFiles(files, previously_defined_modules)
    sources = []
    modules_contained = {}
    modules_used = []
    programs = []
    files.each do |file|
        source = SourceFile.new(file)
        sources.push(source)
        open(file, 'r') do |f|
            f.each_line do |line|
                if line =~ /(?:^|\r|\n)\s*use +(\w+)\b?/i
                    source.addModuleUsed($1.downcase)
                    modules_used.push($1.downcase).uniq!
                end
                if line =~ /(?:^|\r|\n)\s*module +(\w+)\b?/i
                    module_name = $1.downcase
                    if module_name !~ /procedure/i
                        if previously_defined_modules.include?(module_name)
                            puts "*** Error: module #{module_name} is defined in #{file} and #{previously_defined_modules[module_name].source.file_name}"
                            raise
                        end
                        if modules_contained.include?(module_name)
                            puts "*** Error: module #{module_name} is defined in #{file} and #{modules_contained[module_name].source.file_name}"
                            raise
                        end
                        modules_contained[module_name] = Module.new(module_name, source)
                        source.addModuleContained(module_name)
                    end
                end
                if line =~ /(?:^|\r|\n)\s*program +(\w+)\b?/i
                    program_name = $1.downcase
                    programs.push(Program.new(program_name, source))
                end
            end
        end
        source.modules_used.each do |module_name|
            if modules_contained[module_name] && modules_contained[module_name].source.file_name == source.file_name
                source.removeModuleUsed(module_name)
            end
        end
    end
    return sources, modules_contained, modules_used, programs
end

class SourceFile

    def initialize(file_name)
        @file_name = file_name
        @modules_contained = []
        @modules_used = []
    end

    def addModuleUsed(module_name)
        @modules_used.push(module_name).uniq!
    end

    def addModuleContained(module_name)
        @modules_contained.push(module_name).uniq!
    end

    def removeModuleUsed(module_name)
        @modules_used.delete(module_name)
    end

    def file_name
        @file_name
    end

    def modules_used
        @modules_used
    end

    def modules_contained
        @modules_contained
    end

    def object(build_dir)
        File.join(build_dir, Pathname(@file_name).basename.sub_ext('.o').to_s)
    end

    def coverageSpec(build_dir)
        File.join(build_dir, Pathname(@file_name).basename.sub_ext('.gcno').to_s)
    end

    def coverageData(build_dir)
        File.join(build_dir, Pathname(@file_name).basename.sub_ext('.gcda').to_s)
    end

    def coverageOutput(build_dir)
        File.join(build_dir, Pathname(@file_name).basename.to_s + ".gcov")
    end

end

class Module

    def initialize(name, source)
        @name = name
        @source = source
    end

    def name
        @name
    end

    def source
        @source
    end

end

class Program

    def initialize(name, source)
        @name = name
        @source = source
    end

    def name
        @name
    end

    def source
        @source
    end

end

def usedInTest(source, modules_used_in_tests)
    source.modules_contained.each do |module_name|
        if modules_used_in_tests.include?(module_name)
            return true
        end
    end
    return false
end

def containsTestedCode(program, modules_used_in_tests, available_modules)
    modules_used = followModules(program.source, available_modules)
    modules_used.each do |module_name|
        if modules_used_in_tests.include?(module_name)
            return true
        end
    end
    return false
end

def followModules(source, available_modules)
    used_modules = [].concat(source.modules_used)
    source.modules_used.each do |module_name|
        if available_modules.include?(module_name)
            additional_used = followModules(available_modules[module_name].source, available_modules)
            used_modules.concat(additional_used)
        end
    end
    return used_modules.uniq
end

def followDependencies(source, build_dir, available_modules)
    needed_objects = [source.object(build_dir)]
    source.modules_used.each do |module_name|
        if available_modules.include?(module_name)
            additional_needed = followDependencies(available_modules[module_name].source, build_dir, available_modules)
            needed_objects.concat(additional_needed)
        end
    end
    return needed_objects.uniq
end

def usesProductionCode(source, available_modules)
    source.modules_used.each do |module_name|
        if available_modules.include?(module_name)
            return true
        end
    end
    return false
end

def followTestDependencies(source, test_dir, devel_dir, test_modules, main_modules)
    needed_objects = [source.object(test_dir)]
    source.modules_used.each do |module_name|
        if main_modules.include?(module_name)
            additional_needed = followDependencies(main_modules[module_name].source, devel_dir, main_modules)
            needed_objects.concat(additional_needed)
        end
        if test_modules.include?(module_name)
            additional_needed = followTestDependencies(test_modules[module_name].source, test_dir, devel_dir, test_modules, main_modules)
            needed_objects.concat(additional_needed)
        end
    end
    return needed_objects.uniq
end
