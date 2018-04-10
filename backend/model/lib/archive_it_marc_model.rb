class ArchiveItMARCModel < ASpaceExport::ExportModel
  model_for :archive_it_marc

  include JSONModel

  def self.df_handler(name, tag, ind1, ind2, code)
    define_method(name) do |val|
      df(tag, ind1, ind2).with_sfs([code, val])
    end
    name.to_sym
  end

  @archival_object_map = {
    :repository => :handle_repo_code,
    [:title, :dates] => :handle_title,
    :linked_agents => :handle_agents,
    :subjects => :handle_subjects,
    :extents => :handle_extents
  }

  @resource_map = {
    :notes => :handle_notes,
    :finding_aid_description_rules => df_handler('fadr', '040', ' ', ' ', 'e'),
    :ead_location => :handle_ead_loc
  }


  attr_accessor :leader_string
  attr_accessor :controlfield_string
  attr_accessor :controlfield_007
  attr_accessor :full_record
  attr_accessor :wayback_links
  attr_accessor :inclusive_dates

  @@datafield = Class.new do

    attr_accessor :tag
    attr_accessor :ind1
    attr_accessor :ind2
    attr_accessor :subfields


    def initialize(*args)
      @tag, @ind1, @ind2 = *args
      @subfields = []
    end

    def with_sfs(*sfs)
      sfs.each do |sf|
        subfield = @@subfield.new(*sf)
        @subfields << subfield unless subfield.empty?
      end

      return self
    end

  end

  @@subfield = Class.new do

    attr_accessor :code
    attr_accessor :text

    def initialize(*args)
      @code, @text = *args
    end

    def empty?
      if @text && !@text.empty?
        false
      else
        true
      end
    end
  end

  def initialize
    @datafields = {}
  end

  def datafields
    @datafields.map {|k,v| v}
  end


  def self.from_aspace_object(obj)
    self.new
  end

  # 'archival object's in the abstract
  def self.from_archival_object(obj)

    marc = self.from_aspace_object(obj)

    marc.apply_map(obj, @archival_object_map)

    marc
  end

  # subtypes of 'archival object':

  def self.from_resource(obj, wayback_links, inclusive_dates)
    obj[:wayback_links] = wayback_links
    obj[:dates] = inclusive_dates
    marc = self.from_archival_object(obj)
    marc.apply_map(obj, @resource_map)
    marc.send(:handle_wayback_links, wayback_links)
    marc.leader_string = "00000nkiaa22     3u 4500"
    #marc.leader_string[7] = obj.level == 'item' ? 'm' : 'c'

    marc.controlfield_string = assemble_controlfield_string(obj)
    marc.controlfield_007 = "cr cn nnnuunua"

    # to debug
    marc.full_record = obj.to_s
    marc.wayback_links = wayback_links.to_s
    marc.inclusive_dates = inclusive_dates.to_s

    marc
  end

  def self.assemble_controlfield_string(obj)
    # date entered on file
    string = obj['system_mtime'].scan(/\d{2}/)[1..3].join('')
    # continuing resource
    string += 'c'
    # dates
    string += "20uu9999"
    string += "miu"
    string += "nnn"
    12.times { string += ' ' }
    string += "zn"
    string += (obj.language || 'eng')
    string += '  '

    string
  end

  def df!(*args)
    @sequence ||= 0
    @sequence += 1
    @datafields[@sequence] = @@datafield.new(*args)
    @datafields[@sequence]
  end


  def df(*args)
    if @datafields.has_key?(args.to_s)
      @datafields[args.to_s]
    else
      @datafields[args.to_s] = @@datafield.new(*args)
      @datafields[args.to_s]
    end
  end

  def handle_wayback_links(wayback_links)
    wayback_links.each do |wayback_link|
      df!('856', '4', '1').with_sfs(['3', 'Archived website'], ['u', wayback_link], ['z', '2014025 Aa 3'])
    end
  end


  def handle_title(title, inclusive_dates)
    date_codes = []
    if inclusive_dates
      code = "f"
      val = verify_terminal_punctuation(inclusive_dates)
      date_codes.push([code, val])
    end

    if date_codes.length > 0
      df('245', '1', '0').with_sfs(['a', title + ","], *date_codes)
    else
      df('245', '1', '0').with_sfs(['a', verify_terminal_punctuation(title)])
    end
  end

  def handle_repo_code(repository)
    repo = repository['_resolved']
    return false unless repo

    sfa = repo['org_code'] ? repo['org_code'] : "Repository: #{repo['repo_code']}"

    df('852', ' ', ' ').with_sfs(
                        ['a', sfa],
                        ['b', 'BENT'],
                        ['c', 'ELEC'], 
                        ['h', '2014025 Aa 3']
                      )
    df('040', ' ', ' ').with_sfs(['a', repo['org_code']], ['c', repo['org_code']])
  end

  def source_to_code(source)
    if source == 'lcnaf'
      '0'
    else
      ASpaceMappings::MARC21.get_marc_source_code(source)
    end
  end

  def select_non_empty_sfs(sfs)
    sfs.map{|sf| sf if sf[1] && !sf[1].empty?}.compact
  end

  def verify_terminal_punctuation_for_sfs(sfs)
    text_sfs = select_non_empty_sfs(sfs)
    text_sfs[-1][1] = verify_terminal_punctuation(text_sfs[-1][1])
    text_sfs
  end

  def verify_terminal_punctuation(string)
    terminal_punctuation_regex = /[\.\)\-]$/
    if string =~ terminal_punctuation_regex
      string
    else
      string += "."
    end
  end

  def remove_terminal_punctuation_for_sfs(sfs)
    text_sfs = select_non_empty_sfs(sfs)
    text_sfs[-1][1] = remove_terminal_punctuation(text_sfs[-1][1])
    text_sfs
  end

  def remove_terminal_punctuation(string)
    if string.end_with?(".")
      string.gsub(/\.$/, "")
    else
      string
    end
  end

  def handle_subjects(subjects)
    df!('655', ' ', '7').with_sfs(['a', 'Web sites.'], ['2', 'aat'])
    subjects.each do |link|
      subject = link['_resolved']
      term, *terms = subject['terms']
      code, ind2 =  case term['term_type']
                    when 'uniform_title'
                      ['630', source_to_code(subject['source'])]
                    when 'temporal'
                      ['648', source_to_code(subject['source'])]
                    when 'topical'
                      ['650', source_to_code(subject['source'])]
                    when 'geographic', 'cultural_context'
                      ['651', source_to_code(subject['source'])]
                    when 'genre_form', 'style_period'
                      ['655', source_to_code(subject['source'])]
                    when 'occupation'
                      ['656', '7']
                    when 'function'
                      ['656', '7']
                    else
                      ['650', source_to_code(subject['source'])]
                    end
      sfs = [['a', term['term']]]

      terms.each do |t|
        tag = case t['term_type']
              when 'uniform_title'; 't'
              when 'genre_form', 'style_period'; 'v'
              when 'topical', 'cultural_context'; 'x'
              when 'temporal'; 'y'
              when 'geographic'; 'z'
              end
        sfs << [tag, t['term']]
      end

      sfs = verify_terminal_punctuation_for_sfs(sfs)

      if ind2 == '7'
        sfs << ['2', subject['source']]
      end

      df!(code, ' ', ind2).with_sfs(*sfs)
    end
  end


  def handle_primary_creator(linked_agents)
    link = linked_agents.find{|a| a['role'] == 'creator'}
    return nil unless link

    creator = link['_resolved']
    name = creator['display_name']
    ind2 = ' '

    case creator['agent_type']

    when 'agent_corporate_entity'
      code = '110'
      ind1 = '2'
      if name['qualifier']
        if name['subordinate_name_2']
          name['subordinate_name_2'] += " (#{name['qualifier']})"
        elsif name['subordinate_name_1']
          name['subordinate_name_1'] += " (#{name['qualifier']})"
        else
          name['primary_name'] += " (#{name['qualifier']})"
        end
      end

      if name['subordinate_name_2']
        name['primary_name'] = verify_terminal_punctuation(name['primary_name'])
        name['subordinate_name_1'] = verify_terminal_punctuation(name['subordinate_name_1'])
      elsif name['subordinate_name_1']
        name['primary_name'] = verify_terminal_punctuation(name['primary_name'])
      end

      sfs = [
              ['a', name['primary_name']],
              ['b', name['subordinate_name_1']],
              ['b', name['subordinate_name_2']],
              ['n', name['number']],
              ['d', name['dates']],
            ]

    when 'agent_person'
      joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
      name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)
      if name['qualifier']
        name_parts += " (#{name['qualifier']})"
      end

      code = '100'
      sfs = [
              ['a', name_parts],
              ['b', name['number']],
              ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
              ['q', name['fuller_form']],
              ['d', name['dates']],
            ]

    when 'agent_family'
      code = '100'
      ind1 = '3'
      family_name = name['family_name']
      if name['qualifier']
        family_name += " (#{name['qualifier']})"
      end
      sfs = [
              ['a', family_name],
              ['c', name['prefix']],
              ['d', name['dates']],
            ]
    end

    sfs = verify_terminal_punctuation_for_sfs(sfs)
    df(code, ind1, ind2).with_sfs(*sfs)
  end


  def handle_agents(linked_agents)

    handle_primary_creator(linked_agents)

    subjects = linked_agents.select{|a| a['role'] == 'subject'}

    subjects.each_with_index do |link, i|
      subject = link['_resolved']
      name = subject['display_name']
      relator = link['relator']
      next unless relator != 'pbl'
      contributor = relator == 'ctb' ? true : false
      terms = link['terms']
      ind2 = source_to_code(name['source'])

      case subject['agent_type']

      when 'agent_corporate_entity'
        code = contributor ? '710' : '610'
        ind1 = '2'
        if name['qualifier']
          if name['subordinate_name_2']
            name['subordinate_name_2'] += " (#{name['qualifier']})"
          elsif name['subordinate_name_1']
            name['subordinate_name_1'] += " (#{name['qualifier']})"
          else
            name['primary_name'] += " (#{name['qualifier']})"
          end
        end

        if name['subordinate_name_2']
          name['primary_name'] = verify_terminal_punctuation(name['primary_name'])
          name['subordinate_name_1'] = verify_terminal_punctuation(name['subordinate_name_1'])
        elsif name['subordinate_name_1']
          name['primary_name'] = verify_terminal_punctuation(name['primary_name'])
        end

        sfs = [
                ['a', name['primary_name']],
                ['b', name['subordinate_name_1']],
                ['b', name['subordinate_name_2']],
                ['n', name['number']],
              ]

      when 'agent_person'
        joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
        name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)
        if name['qualifier']
          name_parts += " (#{name['qualifier']})"
        end
        ind1 = name['name_order'] == 'direct' ? '0' : '1'
        code = contributor ? '700' : '600'
        sfs = [
                ['a', name_parts],
                ['b', name['number']],
                ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
                ['q', name['fuller_form']],
                ['d', name['dates']],
              ]

      when 'agent_family'
        code = contributor ? '700' : '600'
        ind1 = '3'
        family_name = name['family_name']
        if name['qualifier']
          family_name += " (#{name['qualifier']})"
        end
        sfs = [
                ['a', family_name],
                ['c', name['prefix']],
                ['d', name['dates']],
              ]

      end

      if terms.length > 0
        sfs = remove_terminal_punctuation_for_sfs(sfs)
      end 

      terms.each do |t|
        tag = case t['term_type']
          when 'uniform_title'; 't'
          when 'genre_form', 'style_period'; 'v'
          when 'topical', 'cultural_context'; 'x'
          when 'temporal'; 'y'
          when 'geographic'; 'z'
          end
        sfs << [(tag), t['term']]
      end

      if ind2 == '7'
        sfs << ['2', subject['source']]
      end

      sfs = verify_terminal_punctuation_for_sfs(sfs)
      df(code, ind1, ind2, i).with_sfs(*sfs)
    end


    creators = linked_agents.select{|a| a['role'] == 'creator'}[1..-1] || []
    creators = creators + linked_agents.select{|a| a['role'] == 'source'}

    creators.each do |link|
      creator = link['_resolved']
      name = creator['display_name']
      relator = link['relator']
      terms = link['terms']
      role = link['role']

      ind2 = ' '

      case creator['agent_type']

      when 'agent_corporate_entity'
        code = '710'
        ind1 = '2'
        if name['qualifier']
          if name['subordinate_name_2']
            name['subordinate_name_2'] += " (#{name['qualifier']})"
          elsif name['subordinate_name_1']
            name['subordinate_name_1'] += " (#{name['qualifier']})"
          else
            name['primary_name'] += " (#{name['qualifier']})"
          end
        end

        if name['subordinate_name_2']
          name['primary_name'] = verify_terminal_punctuation(name['primary_name'])
          name['subordinate_name_1'] = verify_terminal_punctuation(name['subordinate_name_1'])
        elsif name['subordinate_name_1']
          name['primary_name'] = verify_terminal_punctuation(name['primary_name'])
        end

        sfs = [
                ['a', name['primary_name']],
                ['b', name['subordinate_name_1']],
                ['b', name['subordinate_name_2']],
                ['n', name['number']],
              ]

      when 'agent_person'
        joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
        name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)
        if name['qualifier']
          name_parts += " (#{name['qualifier']})"
        end
        ind1 = name['name_order'] == 'direct' ? '0' : '1'
        code = '700'
        sfs = [
                ['a', name_parts],
                ['b', name['number']],
                ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
                ['q', name['fuller_form']],
                ['d', name['dates']],
              ]

      when 'agent_family'
        ind1 = '3'
        code = '700'
        family_name = name['family_name']
        if name['qualifier']
          family_name += " (#{name['qualifier']})"
        end
        sfs = [
                ['a', family_name],
                ['c', name['prefix']],
                ['d', name['dates']],
              ]
      end

      sfs = verify_terminal_punctuation_for_sfs(sfs)
      df(code, ind1, ind2).with_sfs(*sfs)
    end

  end


  def handle_notes(notes)

    notes.each do |note|

      prefix =  case note['type']
                when 'dimensions'; "Dimensions"
                when 'physdesc'; "Physical Description note"
                when 'materialspec'; "Material Specific Details"
                when 'physloc'; "Location of resource"
                when 'phystech'; "Physical Characteristics / Technical Requirements"
                when 'physfacet'; "Physical Facet"
                when 'processinfo'; "Processing Information"
                when 'separatedmaterial'; "Materials Separated from the Resource"
                else; nil
                end

      marc_args = case note['type']

                  when 'arrangement', 'fileplan'
                    ['351','b']
                  when 'odd', 'dimensions', 'physdesc', 'materialspec', 'physloc', 'phystech', 'physfacet', 'processinfo', 'separatedmaterial'
                    ['500','a']
                  when 'accessrestrict'
                    ['506','a']
                  when 'scopecontent'
                    ['520', '2', ' ', 'a']
                  when 'abstract'
                    ['520', '2', ' ', 'a']
                  when 'prefercite'
                    ['524', '8', ' ', 'a']
                  when 'acqinfo'
                    ind1 = note['publish'] ? '1' : '0'
                    ['541', ind1, ' ', 'a']
                  when 'relatedmaterial'
                    ['544','a']
                  when 'bioghist'
                    ['545','a']
                  when 'custodhist'
                    ind1 = note['publish'] ? '1' : '0'
                    ['561', ind1, ' ', 'a']
                  when 'appraisal'
                    ind1 = note['publish'] ? '1' : '0'
                    ['583', ind1, ' ', 'a']
                  when 'accruals'
                    ['584', 'a']
                  when 'altformavail'
                    ['535', '2', ' ', 'a']
                  when 'originalsloc'
                    ['535', '1', ' ', 'a']
                  when 'userestrict', 'legalstatus'
                    ['540', 'a']
                  when 'langmaterial'
                    ['546', 'a']
                  else
                    nil
                  end

      unless marc_args.nil?
        text = prefix ? "#{prefix}: " : ""
        text += ASpaceExport::Utils.extract_note_text(note)
        df!(*marc_args[0...-1]).with_sfs([marc_args.last, *Array(text)])
      end

    end
  end


  def handle_extents(extents)
    df!('300').with_sfs(['a', 'Online resource.'])

    extents.each do |ext|
      e = ext['number']
      e << " #{I18n.t('enumerations.extent_extent_type.'+ext['extent_type'], :default => ext['extent_type'])}"

      if ext['container_summary']
        e << " (#{ext['container_summary']})"
      end

      df!('300').with_sfs(['a', e])
    end

  end


  def handle_ead_loc(ead_loc)
    df('555', ' ', ' ').with_sfs(
                                  ['a', "Finding aid online:"],
                                  ['u', ead_loc]
                                )
    df('856', '4', '2').with_sfs(
                                  ['z', "Finding aid online:"],
                                  ['u', ead_loc]
                                )
  end

end