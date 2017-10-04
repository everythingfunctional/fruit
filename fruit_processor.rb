require 'pathname'

class FruitProcessor
    attr_accessor :shuffle

    def initialize
        @shuffle = false
        @spec_hash = {}
    end

    def makeFruitBasket(basket_name, files)
        load_files(files)
        createFruitBasket(basket_name)
    end

    def load_files(files)
        @files = files.uniq

        return if @spec_hash.size != 0

        @files.each do |file|
            parse_method_names file
            gather_specs file
        end
    end

    def parse_method_names file_name
        FruitFortranFile.open(file_name, 'r') do |f|
            @spec_hash[file_name]={}
            @spec_hash[file_name]['methods'] = {}
            @spec_hash[file_name]['methods']['name'] =[]
            @spec_hash[file_name]['methods']['spec'] =[]

            while subroutine_name = f.read_noarg_sub_name
                if subroutine_name.downcase == "setup"
                    @spec_hash[file_name]['setup']='each'
                    next
                end
                if subroutine_name.downcase == "setup_before_all"
                    @spec_hash[file_name]['setup']='all'
                    next
                end
                if subroutine_name.downcase == "teardown"
                    @spec_hash[file_name]['teardown']='each'
                    next
                end
                if subroutine_name.downcase == "teardown_after_all"
                    @spec_hash[file_name]['teardown']='all'
                    next
                end

                #The same condition must be used for storing
                #both subroutine name and spec string.
                #Otherwise number of subroutine names and specs mismatch.
                next if subroutine_name !~ /^test_/
                @spec_hash[file_name]['methods']['name'] << subroutine_name
            end
        end
    end

    def gather_specs file
        spec=''
        FruitFortranFile.open(file, 'r') do |f|
            while subroutine_name = f.read_noarg_sub_name
                next if subroutine_name !~ /^test_/
                spec_var=nil

                while (inside_subroutine = f.gets)
                    break if inside_subroutine =~ /^\s*end\s+subroutine/i
                    break if inside_subroutine =~ /^\s*end *(!.*)?$/i

                    if inside_subroutine =~ /^\s*\!FRUIT_SPEC\s*(.*)$/i
                        spec_var = $1.chomp
                        next
                    end

                    next if inside_subroutine !~ /^\s*character.*::\s*spec\s*=(.*)$/i
                    spec_var = $1
                    spec_var =~ /\s*(["'])(.*)(\1|\&)\s*(!.*)?$/
                    spec_var = $2
                    last_character = $3

                    if last_character == '&'
                        while (next_line = f.gets)
                            next_line.strip!
                            next_line.sub!(/^\&/, '')
                            spec_var += "\n#{next_line.chop}"
                            break if ! end_match(next_line, '&')
                        end
                    end
                end # end of inside subroutine lines

                if spec_var == nil
                    spec=subroutine_name.gsub('test_', '').gsub('_', ' ')
                else
                    spec = spec_var
                end

                @spec_hash[file]['methods']['spec'] << spec
            end # end of each subroutine name
        end # end of file open
    end

    def createFruitBasket(fruit_basket_file)
        test_subroutine_names=[]
        fruit_basket_module_name = Pathname(fruit_basket_file).basename.sub_ext('').to_s


        File.open(fruit_basket_file, 'w') do |f|
            f.write "module #{fruit_basket_module_name}\n"
            f.write "  use fruit\n"
            f.write "contains\n"
        end

        File.open(fruit_basket_file, 'a') do |f|

            files_order = @files
            files_order = files_order.sort_by{ rand } if @shuffle

            files_order.each do |file|
                test_module_name = test_module_name_from_file_path file

                if_ok, error_msg = module_name_consistent? file
                raise error_msg if (!if_ok)

                subroutine_name="#{test_module_name}_all_tests"
                test_subroutine_names << subroutine_name
                f.write "  subroutine #{subroutine_name}\n"
                f.write "    use #{test_module_name}\n"
                f.write "\n"

                method_names = @spec_hash[file]['methods']['name']
                spec_names   = @spec_hash[file]['methods']['spec']

                if (method_names.length != spec_names.length)
                    puts "Error in " + __FILE__ + ": number of methods and specs mismatch"
                    puts "  methods:" + method_names.to_s
                    puts "  specs:" + spec_names.to_s
                end

                if @spec_hash[file]['setup'] != nil
                    if @spec_hash[file]['setup']=='all'
                        f.write "    call setup_before_all\n"
                    end
                end

                if @xml_prefix
                    f.write "    call set_prefix(\"#{@xml_prefix}\")\n"
                end

                method_names = method_names.sort_by{ rand } if @shuffle

                spec_counter = 0
                method_names.each do |method_name|
                    if @spec_hash[file]['setup'] != nil
                        if @spec_hash[file]['setup']=='each'
                            f.write "    call setup\n"
                        end
                    end
                    f.write "    write (*, *) \"  ..running test: #{format_spec_fortran(spec_names[spec_counter], '')}\"\n"
                    f.write "    call set_unit_name('#{format_spec_fortran(spec_names[spec_counter], '')}')\n"
                    f.write "    call run_test_case (#{method_name}, &\n"
                    f.write "                      &\"#{format_spec_fortran(spec_names[spec_counter], '')}\")\n"
                    f.write "    if (.not. is_case_passed()) then\n"
                    f.write "      write(*,*) \n"
                    f.write "      write(*,*) '  Un-satisfied spec:'\n"
                    f.write "      write(*,*) '#{format_spec_fortran(spec_names[spec_counter], '  -- ')}'\n"
                    f.write "      write(*,*) \n"

                    f.write "      call case_failed_xml(\"#{format_spec_fortran(spec_names[spec_counter], '')}\", &\n"
                    f.write "      & \"#{test_module_name}\")\n"
                    f.write "    else\n"
                    f.write "      call case_passed_xml(\"#{format_spec_fortran(spec_names[spec_counter], '')}\", &\n"
                    f.write "      & \"#{test_module_name}\")\n"
                    f.write "    end if\n"

                    if   @spec_hash[file]['teardown'] != nil
                        if @spec_hash[file]['teardown']=='each'
                            f.write "    call teardown\n"
                        end
                    end
                    f.write "\n"
                    spec_counter += 1
                end

                if   @spec_hash[file]['teardown'] != nil
                    if @spec_hash[file]['teardown']=='all'
                        f.write "    call teardown_after_all\n"
                    end
                end

                f.write "  end subroutine #{subroutine_name}\n"
                f.write "\n"

            end
        end

        File.open(fruit_basket_file, 'a') do |f|
            f.write "  subroutine process_fruit_basket\n"
            test_subroutine_names.each do |test_subroutine_name|
                f.write "    call #{test_subroutine_name}\n"
            end
            f.write "  end subroutine process_fruit_basket\n"
            f.write "\n"
            f.write "end module #{fruit_basket_module_name}"
        end
    end

    def test_module_name_from_file_path(file_name)
        Pathname(file_name).basename.sub_ext('').to_s
    end

    def module_name_consistent?(file)
        test_module_name = test_module_name_from_file_path file

        mods = parse_module_name_of_file file

        if mods.size == 1 and mods.include?(test_module_name.downcase)
            return true, ""
        end

        if ! mods or mods.size == 0
            error_msg = "FRUIT Error: No test module (*_test) found in file " + file + "\n"
        elsif mods.size > 1
            error_msg =  "FRUIT Error: More than one tester modules in file #{file}\n"
            error_msg += "  existing modules (*_test): " + mods.join(", ") + "\n"
            error_msg += "  expected module:           " + test_module_name
        elsif ! mods.include?(test_module_name.downcase)
            error_msg  = "FRUIT Error: No test module #{test_module_name} found in file #{file}\n"
            error_msg += "  existing modules (*_test): " + mods.join(", ") + "\n"
            error_msg += "  expected module:           " + test_module_name
        end
        return false, error_msg
    end

    def parse_module_name_of_file(file_name)
        mods = []
        FruitFortranFile.open(file_name, 'r') do |f|
            while module_name = f.read_mod_name
                if module_name =~ /^(\S+_test)$/i
                    test_name = $1.downcase
                    mods.push(test_name)
                end
            end
        end
        return mods
    end

    def format_spec_fortran(spec, spaces)
        indent = "  " + spaces.gsub("-", " ")
        line = spec.gsub("\n", "&\n#{indent}&").gsub("'", "''")
        "#{spaces}#{line}"
    end

end

def end_match (string, match)
    return false if string == nil or string.length ==1
    return string[string.length-1, string.length-1] == match
end

class FruitFortranFile < File

    def read_noarg_sub_name
        while fortran_line = read_fortran_line do
            if fortran_line.match( /^\s*subroutine\s*(\w+)\s*(\!.*)?$/i )
                sub_name = $1
                return sub_name
            end
        end
        return nil
    end

    def read_tester_name_with_arg
        while fortran_line = read_fortran_line do
            if fortran_line.match( /^\s*subroutine\s*(test\w+)\s*\(/i )
                tester_with_arg = $1
                return tester_with_arg
            end
        end
    end

    def read_mod_name
        while fortran_line = read_fortran_line do
            if fortran_line.match( /^\s*module\s*(\w+)\s*(\!.*)?$/i )
                sub_name = $1
                return $1
            end
        end
        return nil
    end

    def read_fortran_line
        conti_line_end =   /\&\s*(\!.*)?[\n\r]*$/
        empty_line    = /^\s*(\!.*)?[\n\r]*$/

        #Skip empty lines
        line = ""
        while (line.match(empty_line))
            line = self.gets
            return line if (not line)
        end

        #Join FORTRAN's coitinuous lines ingoring comments (!) and empty lines.
        while (line.match(conti_line_end))
            line2 = self.gets
            break if (not line2)
            next  if line2.match( empty_line )
            line.sub!(conti_line_end, "")
            line2.sub!(/^\s*\&/, "")
            line = line + line2
        end
        return line
    end

end

def createBasket(basket_name, test_files)
    fp = FruitProcessor.new()
    fp.makeFruitBasket(basket_name, test_files)
end

def createDriver(driver_file, basket_file, results_file)
    driver_program_name = Pathname(driver_file).basename.sub_ext('').to_s
    basket_module_name = Pathname(basket_file).basename.sub_ext('').to_s

    File.open(driver_file, 'w') do |f|
        f.write "program #{driver_program_name}\n"
        f.write "  use fruit\n"
        f.write "  use #{basket_module_name}\n"
        f.write "  call init_fruit\n"
        f.write "  call init_fruit_xml(\"#{results_file}\")\n"
        f.write "  call process_fruit_basket\n"
        f.write "  call fruit_summary\n"
        f.write "  call fruit_summary_xml\n"
        f.write "  call fruit_finalize\n"
        f.write "end program #{driver_program_name}\n"
    end
end
