#!/usr/bin/env ruby
# encoding: utf-8
Version = '20130610-160725'

require 'csv'
require 'fileutils'
require 'active_record'
require 'sushiToolBox'

WORKFLOW_MANAGER='druby://fgcz-s-034:12345'
GSTORE_DIR='/srv/GT/analysis/masaomi/sushi/work_lunch/gstore/sushi'
#GSTORE_DIR='/srv/gstore/projects'


class Hash
  attr_reader :defaults
  alias :set :[]=
  def []=(k,v)
    @defaults ||= {}
    unless @defaults[k]
      @defaults.set(k,v)
    end
    set(k,v)
  end
  def default_value(k)
    @defaults[k]
  end
  def data_type(k)
    @defaults[k].class
  end
  def data_types
    Hash[@defaults.map{|k,v| [k, v.class]}]
  end
end
class SushiApp
  include SushiToolBox
  attr_reader :params
  attr_reader :job_ids
  attr_accessor :dataset_tsv_file
  attr_accessor :parameterset_tsv_file
  attr_accessor :dataset_sushi_id
  attr_accessor :project
  attr_accessor :user
  def initialize
    @gstore_dir = GSTORE_DIR
    @project = nil
    @name = nil
    @params = {}
    @params['cores'] = 1
    @params['ram'] = 1
    @params['scratch'] = 1
    @params['node'] = ''
    @params['process_mode'] = 'SAMPLE'
    @job_ids = []

  end
  def set_input_dataset
    if @dataset_tsv_file
      dataset_tsv = CSV.readlines(@dataset_tsv_file, {:headers=>true, :col_sep=>"\t"})
      @dataset_hash = []
      dataset_tsv.each do |row|
        @dataset_hash << row.to_hash
      end
    elsif @dataset_sushi_id
      @dataset_hash = []
      if dataset = DataSet.find_by_id(@dataset_sushi_id.to_i)
        dataset.samples.each do |sample|
          @dataset_hash << sample.to_hash
        end
      end
    end
    @dataset_hash
  end
  def check_required_columns
    if @dataset_hash and @required_columns and (@required_columns-@dataset_hash.map{|row| row.keys}.flatten.uniq).empty?
      true
    else
      false
    end
  end
  def check_application_paramters
    if @required_params and (@required_params - @params.keys).empty?
      @output_params = @params.clone
    end
  end
  def output_parameters
    @output_params.keys.each do |key|
      @output_params[key] = @params[key]
    end
  end
  def set_user_parameters
    # this should be done in an instance of applicaiton subclass
    if @parameterset_tsv_file
      parameterset_tsv = CSV.readlines(@parameterset_tsv_file, :headers=>true, :col_sep=>"\t")
      parameterset_tsv.each do |row|
        row.headers.each do |header|
          @params[header] ||= row[header]
          @params[header] = if @params.data_type(header) == String
                                    row[header]
                                  else
                                    eval(row[header])
                                  end
        end
      end
    end
  end
  def set_dir_paths
    ## sushi figures out where to put the resulting dataset
    unless @name or @project
      raise "should set #name and #project"
    end
    @name.gsub!(/\s/,'_')
    result_dir_base = [@analysis_category, @name, Time.now.strftime("%Y-%m-%d--%H-%M-%S")].join("_")
    @result_dir = File.join(@project, result_dir_base)
    @scratch_result_dir = File.join("/scratch", result_dir_base)
    @gstore_result_dir = File.join(@gstore_dir, @result_dir)
    set_file_paths
  end
  def prepare_result_dir
    FileUtils.mkdir_p(@scratch_result_dir)
  end
  def job_header
    @scratch_dir = if @params['process_mode'] == 'SAMPLE'
                     @scratch_result_dir + "_" + @dataset['Sample']
                   else
                     @scratch_result_dir
                   end
    @out.print <<-EOF
#!/bin/sh

#### SET THE STAGE
SCRATCH_DIR=#{@scratch_dir}
GSTORE_DIR=#{@gstore_dir}
mkdir $SCRATCH_DIR || exit 1
cd $SCRATCH_DIR || exit 1

    EOF
  end
  def job_footer
    @out.print "#### JOB IS DONE WE PUT THINGS IN PLACE AND CLEAN AUP\n"
    if @output_files
      @output_files.map{|header| next_dataset[header]}.each do |file|
        # in actual case, to save under /srv/gstore/
        if @gstore_dir =~ /srv\/gstore/
          @out.print "gstore-request -w copy ", File.basename(file), " ", File.join(@gstore_dir, file), "\n"
        else
          dest = File.join(@gstore_dir, file)
          dir  = File.dirname(dest)
          @out.print "mkdir -p #{dir} || exit 1\n"
          @out.print "cp -r ", File.basename(file), " ", dest, " || exit 1\n"
        end
      end
      @out.print <<-EOF
cd ~
rm -rf #{@scratch_dir} || exit 1
      EOF
    end
  end
  def job_main
    @out.print "#### NOW THE ACTUAL JOBS STARTS\n"
    @out.print commands, "\n\n"
  end
  def next_dataset
    # this should be overwritten in a subclass
  end
  def commands
    # this should be overwritten in a subclass
  end
  def submit_command(job_script)
    gsub_options = []
    gsub_options << "-c #{@params['cores']}" unless @params['cores'].to_s.empty?
    gsub_options << "-n #{@params['node']}" unless @params['node'].to_s.empty?
    gsub_options << "-r #{@params['ram']}" unless @params['ram'].to_s.empty?
    gsub_options << "-s #{@params['scratch']}" unless @params['scratch'].to_s.empty?
    gsub_options << "-u #{@user}" if @user
    command = "wfm_monitoring --server #{WORKFLOW_MANAGER} #{job_script} #{gsub_options.join(' ')}"
  end
  def submit(job_script)
    command = submit_command(job_script)
    puts "submit: #{command}"
    job_id = `#{command}`
    job_id = job_id.to_i
    unless job_id.to_i > 1
      raise 'failed in job submitting'
    end
    job_id
  end
  def preprocess
    # this should be overwritten in a subclass
  end
  def set_file_paths
    @parameter_file = 'parameters.tsv'
    @input_dataset_file = 'input_dataset.tsv'
    @next_dataset_file = 'next_dataset.tsv'
    @input_dataset_tsv_path = File.join(@gstore_result_dir, @input_dataset_file)
    @parameters_tsv_path = File.join(@gstore_result_dir, @input_dataset_file)
    @next_dataset_tsv_path = File.join(@gstore_result_dir, @next_dataset_file)
  end
  def save_parameters_as_tsv
    file_path = File.join(@scratch_result_dir, @parameter_file)
    CSV.open(file_path, 'w', :col_sep=>"\t") do |out|
      out << @output_params.keys
      out << @output_params.values
    end
    file_path
  end
  def save_input_dataset_as_tsv
    file_path = File.join(@scratch_result_dir, @input_dataset_file)
    CSV.open(file_path, 'w', :col_sep=>"\t") do |out|
      headers = @dataset_hash.map{|row| row.keys}.flatten.uniq
      out << headers
      @dataset_hash.each do |row|
        out << headers.map{|header| row[header]}
      end
    end
    file_path
  end
  def save_next_dataset_as_tsv
    headers = @result_dataset.map{|row| row.keys}.flatten.uniq
    file_path = File.join(@scratch_result_dir, @next_dataset_file)
    CSV.open(file_path, 'w', :col_sep=>"\t") do |out|
      out << headers
      @result_dataset.each do |row_hash|
        out << headers.map{|header| row_hash[header]}
      end
    end
    file_path
  end
  def copy_command(org, dest)
    command = ''
    if @gstore_dir =~ /srv\/gstore/
      command = "gstore-request -w copy #{org} #{dest};"
    else
      dir = File.dirname(dest)
      command << "mkdir -p #{dir};"
      command << "cp #{org} #{dest};"
    end
    command << "\n"
    command
  end
  def copy_input_dataset_parameters
    command = ''
    transfer_files = [@input_dataset_file, @parameter_file]
    transfer_files.each do |file|
      org = File.join(@scratch_result_dir, file)
      dest = File.join(@gstore_result_dir, file)
      command << copy_command(org, dest)
    end
    unless system command
      raise "fails in copying input_dataset files from /scratch to /gstore"
    end
  end
  def copy_next_dataset_job_scripts
    command = ''
    transfer_files = [@next_dataset_file]
    transfer_files.concat @job_scripts.map{|file| File.basename(file)}
    transfer_files.concat @get_log_scripts.map{|file| File.basename(file)}

    transfer_files.each do |file|
      org = File.join(@scratch_result_dir, file)
      dest = File.join(@gstore_result_dir, file)
      command << copy_command(org, dest)
    end
    if system command
      sleep 1
      command = "rm -rf #{@scratch_result_dir}"
      `#{command}`
    else
      raise "fails in copying next_dataset files from /scratch to /gstore"
    end
  end

  def make_job_script
    @out = open(@job_script, 'w')
    job_header
    job_main
    job_footer
    @out.close
  end
  def sample_mode
    @dataset_hash.each do |row|
      @dataset = row
      ## WRITE THE JOB SCRIPT
      @job_script = File.join(@scratch_result_dir, row['Sample']) + '.sh'
      @get_log_script = File.join(@scratch_result_dir, "get_log_#{row['Sample']}.sh")
      make_job_script
      @job_scripts << @job_script
      @get_log_scripts << @get_log_script
      @result_dataset << next_dataset
    end
  end
  def dataset_mode
    @job_script = File.join(@scratch_result_dir, 'job_script.sh')
    @get_log_script = File.join(@scratch_result_dir, "get_log.sh")
    make_job_script
    @job_scripts << @job_script
    @get_log_scripts << @get_log_script
    @result_dataset << next_dataset
  end
  def run
    test_run

    ## the user presses RUN
    prepare_result_dir

    ## copy application data to gstore 
    save_parameters_as_tsv
    save_input_dataset_as_tsv
    copy_input_dataset_parameters


    ## sushi writes creates the job scripts and builds the result data set that is to be generated
    @result_dataset = []
    @job_scripts = []
    @get_log_scripts = []
    if @params['process_mode'] == 'SAMPLE'
      sample_mode
    elsif @params['process_mode'] == 'DATASET'
      dataset_mode
    else 
      #stop
      warn "the process mode (#{@params['process_mode']}) is not defined"
      raise "stop job submitting"
    end

    # job submittion
    @job_scripts.each_with_index do |job_script, i|
      job_id = submit(job_script)
      @job_ids << job_id
      print "Submit job #{File.basename(job_script)} job_id=#{job_id}"
      get_log_script = @get_log_scripts[i]
      open(get_log_script, 'w') do |out|
        out.print "#!/bin/sh\n\n"
        out.print 'CURDIR=`dirname $0`', "\n"
        out.print "wfm_get_log #{job_id} with_err #{WORKFLOW_MANAGER} > $CURDIR/#{File.basename(get_log_script.gsub(/get_log_/,'').gsub(/\.sh/,'.log'))}\n"
      end
    end

		puts
    print 'job scripts: '
    p @job_scripts
    print 'result dataset: '
    p @result_dataset

    save_next_dataset_as_tsv
    copy_next_dataset_job_scripts

    if !@job_ids.empty? and @dataset_sushi_id and dataset = DataSet.find_by_id(@dataset_sushi_id.to_i)
      data_set_arr = []
      headers = []
      rows = []
      data_set_arr = {'DataSetName'=>"results_#{@analysis_category}_#{dataset.name}", 'ProjectNumber'=>@project.gsub(/p/,''), 'ParentID'=>@dataset_sushi_id}
      csv = CSV.readlines(@next_dataset_tsv_path, :col_sep=>"\t")
      csv.each do |row|
        if headers.empty?
          headers = row
        else
          rows << row
        end
      end
      save_data_set(data_set_arr.to_a.flatten, headers, rows)
    end
    # ToDo: delete input/next_dataset parameters file
  end
  def test_run
    set_dir_paths
    preprocess
    set_input_dataset
    set_user_parameters

    failures = 0
    print 'check project name: '
    unless @project
      puts "\e[31mFAILURE\e[0m: project number is required but not found. you should set it in usecase."
      puts "\tex.)"
      puts "\tapp = #{self.class}.new"
      puts "\tapp.project = 'p1001'"
      failures += 1
    else
      puts "\e[32mPASSED\e[0m:\n\t@project=#{@project}"
    end

    print 'check user name: '
    unless @user
      puts "\e[31mWARNING\e[0m: user number is ought to be added but not found. you should set it in usecase. Default will be 'sushi lover'"
      puts "\tex.)"
      puts "\tapp = #{self.class}.new"
      puts "\tapp.user = 'masa'"
    else
      puts "\e[32mPASSED\e[0m:\n\t@user=#{@user}"
    end

    print 'check application name: '
    if @name.to_s.empty?
      puts "\e[31mFAILURE\e[0m: application name is required but not found. you should set it in application class."
      puts "\tex.)"
      puts "\tclass #{self.class}"
      puts "\t def initialize"
      puts "\t  @name = '#{self.class}'"
      puts "\t end"
      puts "\tend"
      failures += 1
    else
      puts "\e[32mPASSED\e[0m:\n\t@name=#{@name}"
    end

    print 'check analysis_category: '
    if @analysis_category.to_s.empty?
      puts "\e[31mFAILURE\e[0m: analysis_category is required but not found. you should set it in application class."
      puts "\tex.)"
      puts "\tclass #{self.class}"
      puts "\t def initialize"
      puts "\t  @analysis_category = 'Mapping'"
      puts "\t end"
      puts "\tend"
      failures += 1
    else
      puts "\e[32mPASSED\e[0m:\n\t@analysis_category=#{@analysis_category}"
    end

    print 'check dataset: '
    if !@dataset_hash or @dataset_hash.empty?
      puts "\e[31mFAILURE\e[0m: dataset is not found. you should set it by using #{self.class}#dataset_sushi_id or #{self.class}#dataset_tsv_file properties"
      puts "\tex.)"
      puts "\tusecase = #{self.class}.new"
      puts "\tusecase.dataset_tsv_file = \"dataset.tsv\""
      failures += 1
    else
      puts "\e[32mPASSED\e[0m:\n\t@dataset_hash.length = #{@dataset_hash.length}"
    end

    print 'check required columns: '
    unless check_required_columns
      puts "\e[31mFAILURE\e[0m: required_column(s) is not found in dataset. you should set it in application class."
      puts "\tex.)"
      puts "\tdef initialize"
      puts "\t  @required_columns = ['Sample', 'Read1']"
      puts
      failures += 1
    else
      puts "\e[32mPASSED\e[0m:"
    end
    puts "\trequired columns: #{@required_columns}"
    puts "\tdataset  columns: #{@dataset_hash.map{|row| row.keys}.flatten.uniq}" if @dataset_hash

    print 'check required parameters: '
    unless check_application_paramters
      puts "\e[31mFAILURE\e[0m: required_param(s) is not set yet. you should set it in usecase"
      puts "\tmissing params: #{@required_params-@params.keys}" if @required_params
      puts "\tex.)"
      puts "\tusecase = #{self.class}.new"
      if @required_params
        puts "\tusecase.params['#{(@required_params-@params.keys)[0]}'] = parameter"
      else
        puts "\tusecase.params['parameter name'] = default_parameter"
      end
      puts
      failures += 1
    else
      puts "\e[32mPASSED\e[0m:"
    end
    puts "\tparameters: #{@params.keys}"
    puts "\trequired  : #{@required_params}"

    print 'check next dataset: '
    @dataset={}
    unless self.next_dataset
      puts "\e[31mFAILURE\e[0m: next dataset is not set yet. you should overwrite SushiApp#next_dataset method in #{self.class}"
      puts "\tnote: the return value should be Hash (key: column title, value: value in a tsv table)"
      failures += 1
    else
      puts "\e[32mPASSED\e[0m:"
    end

    print 'check output files: '
    if !@output_files or @output_files.empty?
      puts "\e[31mWARNING\e[0m: no output files. you will not get any output files after the job running. you can set @output_files (array) in #{self.class}"
      puts "\tnote: usually it should be define in initialize method"
      puts "\t      the elements of @output_files should be chosen from #{self.class}#next_dataset.keys"
      puts "\t      #{self.class}#next_dataset.keys: #{self.next_dataset.keys}" if self.next_dataset
    else
      puts "\e[32mPASSED\e[0m:"
    end

    print 'check commands: '
    if @params['process_mode'] == 'SAMPLE'
      @dataset_hash.each do |row|
        @dataset = row
        unless com = commands
          puts "\e[31mFAILURE\e[0m: any commands is not defined yet. you should overwrite SushiApp#commands method in #{self.class}"
          puts "\tnote: the return value should be String (this will be in the main body of submitted job script)"
          failures += 1
        else
          puts "\e[32mPASSED\e[0m:"
          puts "generated command will be:"
          puts "\t"+com.split(/\n/).join("\n\t")+"\n"
        end
      end
    elsif @params['process_mode'] == 'DATASET'
      unless com = commands
        puts "\e[31mFAILURE\e[0m: any commands is not defined yet. you should overwrite SushiApp#commands method in #{self.class}"
        puts "\tnote: the return value should be String (this will be in the main body of submitted job script)"
        failures += 1
      else
        puts "\e[32mPASSED\e[0m:"
        puts "generated command will be:"
        puts "\t"+com.split(/\n/).join("\n\t")+"\n"
      end
    end

    print 'check workflow manager: '
    begin
      hello = `wfm_hello #{WORKFLOW_MANAGER}`
    rescue
    end
    unless hello =~ /hello/
      puts "\e[31mFAILURE\e[0m: workflow_manager does not reply. check if workflow_manager is working"
      failures += 1
    else
      puts "\e[32mPASSED\e[0m:"
    end

    if failures > 0
      puts
      puts "\e[31mFailures (#{failures})\e[0m: All failures should be solved"
      raise "test run fails"
    else
      puts "All checks \e[32mPASSED\e[0m"
    end
  end
end


