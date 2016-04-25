require 'sushi_fabric'
require_relative 'global_variables'
include GlobalVariables

class FastqcMinimal < SushiFabric::SushiApp
  def initialize
    super
    @name = 'FastqcMinimal'
    @analysis_category = 'QC'
    @required_columns = ['Name','Read1']
    @required_params = []
  end
  def next_dataset
    {
     'Name'=>@dataset['Name'], 
     'Report [Link, File]'=>File.join(@result_dir, File.basename(@dataset['Read1'].to_s).gsub('.fastq.gz', '_fastqc.zip'))
    }
  end
  def commands
    "fastqc --extract -o . -t #{@params['cores']} #{@gstore_dir}/#{@dataset['Read1']}"
  end
end
