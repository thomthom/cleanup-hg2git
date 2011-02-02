#-----------------------------------------------------------------------------
# Compatible: SketchUp 7.1+
#             (other versions untested)
#-----------------------------------------------------------------------------
#
# SketchUp versions prior to SketchUp 7.1 are highly prone to loss of geometry.
# Users are advised to not use this plugin unless they run 7.1 or higher.
#
#-----------------------------------------------------------------------------
#
# FEATURES
#
# * Fixes duplicate component definition names ( When in model scope )
# * Purge unused items
# * Erase hidden geometry
# * Erase duplicate faces
# * Erase lonely edges ( Except edges on cut plane )
# * Remove edge material
# * Repair split edges
# * Smooth & soft edges
# * Put edges and faces to Layer0
# * Merge identical materials
# * Merge connected co-planar faces
#
#-----------------------------------------------------------------------------
#
# CHANGELOG
#
# 3.0.0 - 01.02.2011
#		 * Version 3
#
#-----------------------------------------------------------------------------
#
# TODO
#
# * Detect Materials not in Material list
# * Merge Styles
# * Detect small faces
#
#-----------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-----------------------------------------------------------------------------

require 'sketchup.rb'
require 'TT_Lib2/core.rb'

TT::Lib.compatible?('2.5.0', 'CleanUp�')

#-----------------------------------------------------------------------------


module TT::Plugins::CleanUp
  
  ### CONSTANTS ### --------------------------------------------------------
  
  VERSION = '3.0.0'.freeze
  PREF_KEY = 'TT_CleanUp'.freeze
  
  SCOPE_MODEL = 'Model'.freeze
  SCOPE_LOCAL = 'Local'.freeze
  SCOPE_SELECTED = 'Selected'.freeze
  
  GROUND_PLANE = [ ORIGIN, Z_AXIS ]
  
  
  ### MENU & TOOLBARS ### --------------------------------------------------
  
  unless file_loaded?( __FILE__ )
    m = TT.menu('Plugins')
    m.add_item('CleanUp�')  { self.show_cleanup_ui }
  end 
  
  
  ### MAIN SCRIPT ### ------------------------------------------------------
 
  
  def self.show_cleanup_ui
    model = Sketchup.active_model
    
    # Default value for Scope
    if model.selection.empty?
      if model.active_path.nil?
        default_scope = SCOPE_MODEL
      else
        default_scope = SCOPE_LOCAL
      end
    else
      default_scope = SCOPE_SELECTED
    end
    
    window_options = {
      :title => 'CleanUp�',
      :pref_key => PREF_KEY,
      :modal => true,
      :accept_label => 'CleanUp',
      :cancel_label => 'Cancel',
      :align => 0.3,
      :left => 200,
      :top => 100,
      :width => 290,
      :height => 785
    }
    i = TT::GUI::Inputbox.new(window_options)
    #i.add_control( {
    #  :key   => :progressbar,
    #  :label => 'Use Progressbar',
    #  :value => true,
    #  :group => 'General'
    #} )
    i.add_control( {
      :key     => :scope,
      :label   => 'Scope',
      :value   => default_scope,
      :no_save => true,
      :options => [SCOPE_MODEL, SCOPE_LOCAL, SCOPE_SELECTED],
      :type    => TT::GUI::Inputbox::CT_RADIOBOX,
      :group   => 'General'
    } )
    i.add_control( {
      :key   => :validate,
      :label => 'Validate Results',
      :tooltip => <<EOT,
Recommended!

Runs SketchUp's validation tool after cleaning the model to ensure a healthy model.
EOT
      :value => true,
      :group => 'General'
    } )
    i.add_control( {
      :key   => :statistics,
      :label => 'Show Statistics',
      :tooltip => <<EOT,
Shows a summary of what was done at the end of the cleanup.
EOT
      :value => true,
      :group => 'General'
    } )
    i.add_control( {
      :key   => :purge,
      :label => 'Purge Unused',
      :tooltip => <<EOT,
Purges all unused items in model. (Components, Materials, Styles, Layers)
EOT
      :value => true,
      :group => 'Optimisations'
    } )
    i.add_control( {
      :key   => :erase_hidden,
      :label => 'Erase Hidden Geometry',
      :tooltip => <<EOT,
Erases all hidden entities in the current scope.
EOT
      :value => false,
      :group => 'Optimisations'
    } )
    i.add_control( {
      :key   => :remove_duplicate_faces,
      :label => 'Erase Duplicate Faces',
      :tooltip => <<EOT,
Warning: Very slow!

Tries to detect faces occupying the same space. Only use if you need to correct models with overlapping faces.
EOT
      :value => false,
      :group => 'Optimisations'
    } )
    i.add_control( {
      :key   => :geom_to_layer0,
      :label => 'Geometry to Layer0',
      :tooltip => <<EOT,
Puts all edges and faces on Layer0.
EOT
      :value => false,
      :group => 'Layers'
    } )
    i.add_control( {
      :key   => :merge_materials,
      :label => 'Merge Identical Materials',
      :tooltip => <<EOT,
Note: Processes all materials in the model, not just the current scope!

Merges all identical materials in the model, ignoring metadata attributes.
EOT
      :value => false,
      :group => 'Materials'
    } )
    i.add_control( {
      :key   => :merge_ignore_attributes,
      :label => 'Ignore Attributes',
      :tooltip => <<EOT,
When checked, attribute meta data is ignored. (Might include render engine data.)
EOT
      :value => true,
      :group => 'Materials'
    } )
    i.add_control( {
      :key   => :merge_faces,
      :label => 'Merge Coplanar Faces',
      :tooltip => <<EOT,
Removes edges separating coplanar faces.
EOT
      :value => true,
      :group => 'Coplanar Faces'
    } )
    i.add_control( {
      :key   => :merge_ignore_normals,
      :label => 'Ignore Normals',
      :tooltip => <<EOT,
When checked, faces are considered coplanar even if they are facing the opposite direction to each other.
EOT
      :value => false,
      :group => 'Coplanar Faces'
    } )
    i.add_control( {
      :key   => :merge_ignore_materials,
      :label => 'Ignore Materials',
      :tooltip => <<EOT,
When checked, faces are merged even though their material is different.
EOT
      :value => false,
      :group => 'Coplanar Faces'
    } )
    i.add_control( {
      :key   => :merge_ignore_uv,
      :label => 'Ignore UV',
      :tooltip => <<EOT,
When checked, faces are merged even though their UV mapping is different.
EOT
      :value => true,
      :group => 'Coplanar Faces'
    } )
    # http://forums.sketchucation.com/viewtopic.php?f=323&t=33473&hilit=cleanup
    #i.add_control( {
    #  :key   => :repair_small_faces,
    #  :label => 'Repair Small Faces',
    #  :value => false,
    #  :group => 'Faces'
    #} )
    i.add_control( {
      :key   => :repair_split_edges,
      :label => 'Repair Split Edges',
      :value => true,
      :group => 'Edges'
    } )
    i.add_control( {
      :key   => :remove_lonely_edges,
      :label => 'Erase Lonely Edges',
      :tooltip => <<EOT,
Removes all edges not connected to any face.
EOT
      :value => true,
      :group => 'Edges'
    } )
    i.add_control( {
      :key   => :remove_edge_materials,
      :label => 'Remove Edge Materials',
      :value => false,
      :group => 'Edges'
    } )
    i.add_control( {
      :key   => :smooth_angle,
      :label => 'Smooth Edges by Angle',
      :value => 0.0,
      :group => 'Edges'
    } )
    i.prompt { |results|
      self.cleanup!(results) unless results.nil?
    }
  end
  
  
  # The order which the various cleanup process is important to ensure optimal
  # cleanup and decent performance.
  def self.cleanup!(options)
    # <debug>
    #options.each { |k,v| puts "#{k.to_s.ljust(25)} #{v}" }
    # </debug>
    
    # Warn users of SketchUp older than 7.1
    msg = 'Sketchup prior to 7.1 has a bug which might lead to loss of geometry. Do you want to continue?'
    if not TT::Sketchup.newer_than?(7, 1, 0)
      return if UI.messagebox( msg, MB_YESNO ) == 7 # No
    end
    
    model = Sketchup.active_model
    model.start_operation('Cleanup Model', true)
    
    scope = options[:scope]
    
    # Keep statistics of the cleanup.
    stats = {}
    stats['Total Elapsed Time'] = Time.now	
    
    # Ensure no material is active, as that would prevent the model from being
    # removed from the model.
    model.materials.current = nil
    
    ### Erase Hidden ###
    if options[:erase_hidden]
      stats['Hidden Entities Erased'] = self.erase_hidden( model, scope )
    end
    
    ### Purge ###
    # Purge unused geometry before processing anything else.
    if options[:purge]
      stats['Purged Components'] = model.definitions.length
      Sketchup.status_text = 'Purging Components...'
      model.definitions.purge_unused
      stats['Purged Components'] -= model.definitions.length
    end
    
    ### Fix Duplicate Component Names ###
    # (?) Optional?
    if scope == SCOPE_MODEL
      fixed_components = self.fix_component_names
      if fixed_components > 0
        puts "> Fixed Duplicate Component Names: #{fixed_components}"
        stats['Duplicate Component Names Fixed'] = fixed_components
      end
    end
    
    ### Merge Materials ###
    if options[:merge_materials] 
      count = self.merge_similar_materials( model, options )
      stats['Materials Merged'] = count
    end
    
    ### Merge Coplanar Faces ###
    if options[:merge_faces] 
      stats['Edges Reduced'] = 0
      stats['Faces Reduced'] = model.number_faces if model.respond_to?(:number_faces)
      progress = TT::Progressbar.new( self.count_scope_entity( scope, model ) , 'Merging Faces' )
      count = self.each_entity_in_scope( scope, model ) { |e|
        progress.next
        self.merge_connected_faces(e, options)
      }
      stats['Edges Reduced'] += count
      stats['Faces Reduced'] -= model.number_faces if model.respond_to?(:number_faces)
    end
    
    ### Erase Duplicate Faces ###
    if options[:remove_duplicate_faces]
      stats['Faces Reduced'] ||= 0
      progress = TT::Progressbar.new( self.count_scope_entity( scope, model ), 'Removing duplicate faces' )
      count = self.each_entities_in_scope( scope, model ) { |entities|
        self.erase_duplicate_faces(entities, progress)      
      }
      stats['Faces Reduced'] += count
      
      # Merge Coplanar Faces once more after removing duplicate faces.
      # Duplicate faces is not run first because it is so slow - pre-processing
      # and removing as many faces as possible is best.
      if options[:merge_faces] 
        stats['Edges Reduced'] = 0
        stats['Faces Reduced'] = model.number_faces if model.respond_to?(:number_faces)
        progress = TT::Progressbar.new( self.count_scope_entity( scope, model ), 'Merging Faces' )
        count = self.each_entity_in_scope( scope, model ) { |e|
          progress.next
          self.merge_connected_faces(e, options) 
        }
        stats['Edges Reduced'] += count
        stats['Faces Reduced'] -= model.number_faces if model.respond_to?(:number_faces)
      end
    end
    
    ### Repair Split Edges ###
    if options[:remove_lonely_edges] 
      stats['Edges Reduced'] ||= 0
      progress = TT::Progressbar.new( self.count_scope_entity( scope, model ), 'Removing lonely edges' )
      count = self.each_entities_in_scope( scope, model ) { |entities|
        self.erase_lonely_edges(entities, progress)
      }
      stats['Edges Reduced'] += count
    end
    
    ### Repair Split Edges ###
    if options[:repair_split_edges]
      stats['Edges Reduced'] ||= 0
      progress = TT::Progressbar.new( self.count_scope_entity( scope, model ), 'Repairing split edges' )
      count = self.each_entities_in_scope( scope, model ) { |entities|
        TT::Edges.repair_splits( entities, progress )
      }
      stats['Edges Reduced'] += count
    end
    
    ### Post-process edges ###
    progress = TT::Progressbar.new( self.count_scope_entity( scope, model ), 'Post Processing' )
    self.each_entity_in_scope( scope, model ) { |e|
      progress.next
      self.post_process(e, options)
    }
    
    ### Purge ###
    if options[:purge]
      # In case some components have become unused.
      size = model.definitions.length
      Sketchup.status_text = 'Purging Components...'
      model.definitions.purge_unused
      stats['Purged Components'] += size - model.definitions.length
      TT::Sketchup.refresh

      stats['Purged Layers'] = model.layers.length
      Sketchup.status_text = 'Purging Layers...'
      model.layers.purge_unused
      stats['Purged Layers'] -= model.layers.length
      TT::Sketchup.refresh
      
      stats['Purged Materials'] = model.materials.length
      Sketchup.status_text = 'Purging Materials...'
      model.materials.purge_unused
      stats['Purged Materials'] -= model.materials.length
      TT::Sketchup.refresh
      
      stats['Purged Styles'] = model.styles.count
      Sketchup.status_text = 'Purging Styles...'
      model.styles.purge_unused
      stats['Purged Styles'] -= model.styles.count
      TT::Sketchup.refresh
    end
    
    model.commit_operation
    TT::Sketchup.refresh
    
    ### Compile Statistics ###
    elapsed_time = TT::format_time( Time.now - stats['Total Elapsed Time'] )
    stats['Total Elapsed Time'] = elapsed_time
    # (?) Remove entries with 0 results?
    formatted_stats = stats.collect{|k,v|"> #{k}: #{v}"}.sort.join("\n")
    formatted_stats = "Cleanup Statistics:\n#{formatted_stats}"
    puts formatted_stats
    if options[:statistics]
      UI.messagebox( formatted_stats, MB_MULTILINE )
    end
    
    ### Validity Check ###
    if options[:validate]
      # This must be done outside any operations as it creates its own undo
      # entry in the undo-stack.
      # (i) Delay to avoid UI lockup - seem to be related to using the Inputbox class.
      #self.validity_check
      UI.start_timer(0, false) { self.validity_check }
    end
    
    UI.refresh_inspectors
    
    Sketchup.status_text = 'Done!'
    
    # (!) Catch errors. Commit, inform user, offer to undo.
  end
  
  
  def self.count_scope_entity( scope, model )
    case scope
    when SCOPE_MODEL
      TT::Model.count_unique_entity( model, false )
    when SCOPE_LOCAL
      TT::Entities.count_unique_entity( model.active_entities )
    when SCOPE_SELECTED
      TT::Entities.count_unique_entity( model.selection )
    else
      raise ArgumentError, 'Invalid Scope'
    end
  end
  
  
  # (?) Unused?
  def self.count_scope_entities( scope, model )
    case scope
    when SCOPE_MODEL
      TT::Model.count_unique_entities( model, false )
    when SCOPE_LOCAL
      TT::Entities.count_unique_entities( model.active_entities )
    when SCOPE_SELECTED
      TT::Entities.count_unique_entities( model.selection )
    else
      raise ArgumentError, 'Invalid Scope'
    end
  end
  
  
  # Model entity iterator. Yields all unique entities in the scope.
  def self.each_entity_in_scope( scope, model, &block )
    case scope
    when SCOPE_MODEL
      TT::Model.each_entity( model, false, &block )
    when SCOPE_LOCAL
      TT::Entities.each_entity( model.active_entities, &block )
    when SCOPE_SELECTED
      TT::Entities.each_entity( model.selection, &block )
    else
      raise ArgumentError, 'Invalid Scope'
    end
  end
  
  
  def self.each_entities_in_scope( scope, model, &block )
    case scope
    when SCOPE_MODEL
      TT::Model.each_entities( model, false, &block )
    when SCOPE_LOCAL
      TT::Entities.each_entities( model.active_entities, &block )
    when SCOPE_SELECTED
      TT::Entities.each_entities( model.selection, &block )
    else
      raise ArgumentError, 'Invalid Scope'
    end
  end
  
  
  # Triggers SketchUp's model validity check.
  def self.validity_check
    Sketchup.status_text = 'Checking validity. Please wait...'
    Sketchup.send_action(21124)
  end
  
  
  # Post-process edges. Smooth and remove materials.
  def self.post_process(e, options)
    # Put on Layer 0
    if options[:geom_to_layer0]
      if e.is_a?( Sketchup::Edge ) || e.is_a?( Sketchup::Face )
        # Ensure the visibility inherited from the layer is transfered to the
        # entity.
        unless e.layer.visible?
          e.hidden = true
        end
        e.layer = nil
      end
    end
    return nil unless e.is_a?(Sketchup::Edge)
    # Remove Edge Material
    e.material = nil if options[:remove_edge_materials]
    # Smooth Edge
    if options[:smooth_angle] && options[:smooth_angle] > 0 && e.faces.length == 2
      angle = e.faces[0].normal.angle_between(e.faces[1].normal)
      if angle.radians.abs <= options[:smooth_angle]
        e.smooth = true
        e.soft = true
      end
    end
  end

  
  # Erase edges not connected to faces,
  # and edges that connects to the same face multiple times.
  def self.erase_lonely_edges(entities, progress)
    return 0 if entities.length == 0
    # Because entities can be an array, need to get a reference to the parent
    # Sketchup::Entities collection
    parent = entities.find { |e| e.valid? }.parent
    # Detect cutout component and protect edges on cut-plane.
    cutout = parent.is_a?( Sketchup::ComponentDefinition ) && parent.behavior.cuts_opening?
    # Find all edges not connected to any face and edges where all connected faces
    # are the same edge (some odd SketchUp glitch).
    edges = []
    for e in entities.to_a
      progress.next
      next unless e.valid? && e.is_a?(Sketchup::Edge)
      # Protect edges on the cut plane for cutouts
      next if cutout && e.vertices.all? { |v| v.position.on_plane?( GROUND_PLANE ) }
      # Pick out edges that doesn't connect to any faces or connect to the same
      # face multiple times. (Some times Sketchup edges has strange connections
      # like that.)
      if e.faces.size == 0 || 
         ( e.faces.size > 1 && e.faces.all?{ |f| f == e.faces[0] } )
        edges << e
      end
    end
    parent.entities.erase_entities(edges)
    return edges.size
  end
  
  
  # Merge coplanar faces by erasing the separating edge.
  # (?) Find all shared edges and erase them? Or was that tried earlier without
  # success?
  #
  # Returns true if the given entity was an edge separating two coplanar edges.
  # Return false otherwise.
  def self.merge_connected_faces(e, options)   
    return false unless e.valid? && e.is_a?(Sketchup::Edge)
    # Coplanar edges only have two faces connected.
    return false unless e.faces.size == 2
    f1, f2 = e.faces
    # Ensure normals are correct.
    unless options[:merge_ignore_normals]
      unless f1.normal.samedirection?(f2.normal)
        return false
      end
    end
    # Don't try to merge faces sharing the same set of vertices.
    return false if self.face_duplicate?(f1, f2)
    # Ensure materials match.
    unless options[:merge_ignore_materials]
      # Verify materials.
      if f1.material == f2.material && f1.back_material == f2.back_material
        # Verify UV mapping match.
        unless f1.material.nil? || f1.material.texture.nil? || options[:merge_ignore_uv]
          return false unless self.continuous_uv?(f1, f2, e)
        end # unless options[:merge_ignore_uv]
      else
        return false
      end
    end # unless options[:merge_ignore_materials]
    # Ensure faces are co-planar.
    return false unless self.faces_coplanar?(f1, f2)
    # Edge passed all checks - safe to erase.
    e.erase!
    true
  end
  
  
  # Finds multiple faces for the same set of vertices and reduce them to one.
  # Erases faces overlapped by a larger face.
  # (!) Review this method.
  def self.erase_duplicate_faces(entities, progress)
    Sketchup.status_text = "Removing duplicate faces..."
    
    return 0 if entities.length == 0
    entities = entities.select { |e| e.valid? }
    parent = entities[0].parent.entities
    
    faces = entities.select { |e| e.is_a?(Sketchup::Face) }
    duplicates = [] # Confirmed duplicates.
    
    for face in faces.to_a
      progress.next
      next unless face.valid?
      next if duplicates.include?(face)
      connected = face.edges.map { |e| e.faces }
      connected.flatten!
      connected.uniq!
      connected &= entities
      connected.delete(face)
      for f in (connected - duplicates)
        next unless f.valid?
        duplicates << f if face_duplicate?(face, f, true)
      end # for
    end
    parent.erase_entities(duplicates) unless duplicates.empty?
    
    return duplicates.length
  end
  
  
  # Returns true if the two faces connected by the edge has continuous UV mapping.
  # UV's are normalized to 0.0..1.0 before comparison.
  def self.continuous_uv?( face1, face2, edge )
    tw = Sketchup.create_texture_writer
    uvh1 = face1.get_UVHelper( true, true, tw )
    uvh2 = face2.get_UVHelper( true, true, tw )
    p1 = edge.start.position
    p2 = edge.end.position
    self.uv_equal?( uvh1.get_front_UVQ(p1), uvh2.get_front_UVQ(p1) ) &&
    self.uv_equal?( uvh1.get_front_UVQ(p2), uvh2.get_front_UVQ(p2) ) &&
    self.uv_equal?( uvh1.get_back_UVQ(p1), uvh2.get_back_UVQ(p1) ) &&
    self.uv_equal?( uvh1.get_back_UVQ(p2), uvh2.get_back_UVQ(p2) )
  end
  
  
  # Normalize UV's to 0.0..1.0 and compare them.
  def self.uv_equal?( uvq1, uvq2 )
    uv1 = uvq1.to_a.map { |n| n % 1 }
    uv2 = uvq2.to_a.map { |n| n % 1 }
    uv1 == uv2
  end
  
  
  # Determines if two faces are coplanar.
  def self.faces_coplanar?(face1, face2)
    vertices = face1.vertices + face2.vertices
    plane = Geom.fit_plane_to_points( vertices )
    vertices.all? { |v| v.position.on_plane?(plane) }
  end
  
  
  # Determines if two faces occupy the same space.
  # (!) Review
  def self.face_duplicate?(face1, face2, overlapping = false)
    return false if face1 == face2
    v1 = face1.outer_loop.vertices
    v2 = face2.outer_loop.vertices
    return true if (v1 - v2).empty? && (v2 - v1).empty?
    #return true if overlapping && (v2 - v1).empty? # (!) error
    # A wee hack to determine if a face2 is fully overlapped by face1.
    if overlapping && (v2 - v1).empty?
      edges = (face2.outer_loop.edges - face1.outer_loop.edges)
      unless edges.empty?
        point = edges[0].start.position.offset(edges[0].line[1], 0.01)
        return true if face1.classify_point(point) <= 4
      end
    end
    return false
  end
  
  
  def self.merge_similar_materials( model, options )
    c = 0
    progress = TT::Progressbar.new( model.materials, 'Finding similar materials' )
    materials = model.materials
    stack = materials.to_a
    
    matches = {}
    
    # Build list of replacements
    until stack.empty?
      progress.next
      proto_material = stack.shift
      ad1 = proto_material.attribute_dictionaries
      for material in stack.to_a
        next unless material.color.to_a == proto_material.color.to_a
        next unless material.materialType == proto_material.materialType
        if material.texture
          texture = material.texture
          proto_texture = material.texture
          next unless texture.filename == proto_texture.filename
          next unless texture.width == proto_texture.width
          next unless texture.height == proto_texture.height
          next unless texture.image_width == proto_texture.image_width
          next unless texture.image_height == proto_texture.image_height
        end
        # Compare attribute dictionaries
        unless options[:merge_ignore_attributes]
          ad2 = material.attribute_dictionaries
          next unless TT::Attributes.dictionaries_equal?( ad1, ad2 )
        end
        
        matches[ material ] = proto_material
        stack.delete( material )
        c += 1
        
      end # for
    end # until stack.empty?
    
    # Replace materials
    count = TT::Model.count_unique_entity( model, false )
    progress = TT::Progressbar.new( count, 'Merging materials' )
    e = nil # Init variables for speed
    TT::Model.each_entity( model, false ) { |e|
      if e.respond_to?( :material )
        if replacement = matches[e.material]
          e.material = replacement
        end
      end
      if e.respond_to?( :back_material )
        if replacement = matches[e.back_material]
          e.back_material = replacement
        end
      end
      progress.next
    }
    
    # Remove materials
    # No need to remove materials if we later purge everything.
    unless options[:purge]
      self.remove_materials( model, matches.keys )
    end
    
    c
  end
  
  
  def self.replace_materials( model, old_materials, new_material )
    count = TT::Model.count_unique_entity( model, false )
    progress = TT::Progressbar.new( count, "Merging material '#{new_material.display_name}'" )
    e = nil # Init variables for speed
    TT::Model.each_entity( model, false ) { |e|
      if e.respond_to?( :material )
        e.material = new_material if old_materials.include?( e.material )
      end
      if e.respond_to?( :back_material )
        e.back_material = new_material if old_materials.include?( e.back_material )
      end
      progress.next
    }
  end
  
  
  def self.remove_materials( model, materials )
    m = model.materials
    if m.respond_to?( :remove )
      for material in materials
        m.remove( material )
      end
    else
      # Workaround for SketchUp versions older than 8.0M1. Add all materials
      # except the one to be removed to temporary groups and purge the materials.
      temp_group = model.entities.add_group
      for material in model.materials
        next if materials.include?( material )
        g = temp_group.add_group
        g.material = material
      end
      materials.purge_unused
      temp_group.erase!
      true
    end
  end
  
  
  def self.erase_hidden( model, scope )
    entity_count = self.count_scope_entity( scope, model )
    progress = TT::Progressbar.new( entity_count, 'Erasing hidden entities' )
    e = nil # Init variables for speed
    count = self.each_entity_in_scope( scope, model ) { |e|
      progress.next
      erased = false
      if e.valid?
        if e.is_a?( Sketchup::Edge )
          # Edges needs to be checked further
          if e.hidden? || e.soft? || !e.layer.visible?
            unless self.edge_protected?( e )
              e.erase!
              erased = true
            end
          end
        elsif e.hidden? || !e.layer.visible?
          # Everything else is safe to erase.
          e.erase!
          erased = true
        end # if edge?
      end
      erased
    }
  end
  
  
  def self.edge_protected?( edge )
    if edge.faces.any? { |edge| edge.visible? || edge.layer.visible? }
      return true
    end
    parent = edge.parent
    if parent.is_a?( Sketchup::ComponentDefinition ) && parent.behavior.cuts_opening?
      return true if edge.vertices.all? { |v| v.position.on_plane?( GROUND_PLANE ) }
    end
    false
  end
  
  
  # (!) Needs testing
  #
  # There has been cases where materials doesn't appear in the material list.
  # A material can be picked from an Image and used in the model where it won't
  # be listed in the material list UI, nor when model.material.each is iterated.
  #
  # With the introduction of model.materials.remove which doesn't automatically
  # remove the material from the model entities, there is a risk of ending up
  # with models where the material is not listed in the UI or even accessible
  # via the model.materials collection.
  #
  # These material can be removed or recreated.
  def self.fix_orphan_materials( model, options )
    materials = model.materials
    repair_materials = options[:fix_materials] == 'Repair'
    
    all_materials = (0...materials.count).map { |i| materials[i] }
    image_materials = all_materials.reject { |m| materials.include?(m) }
    
    # Build hash lookup for better performance.
    material_type = {}
    for material in all_materials
      if image_materials.include?( material )
        material_type[ material ] = :image
      else
        material_type[ material ] = :material
      end
    end
    
    setter = {
      :material => :material=,
      :back_material => :back_material=
    }
    
    # key: Orphan Material
    # value: New Repaired Material
    repairs = {}
    
    orphans = Set.new
    entity_count = TT::Model.count_unique_entity( model, false )
    progress = TT::Progressbar.new( entity_count, 'Looking for orphan materials' )
    e, key = nil # Init variables for speed
    TT::Model.each_entity( model, false ) { |e|
      progress.next
      
      [ :material, :back_material ].each { |key|
        next unless e.respond_to?( key )
        material = e.send( key )
        type = material_type[ material ]
        unless type == :material
          if repair_materials
            unless replacement = repairs[ material ]
              replacement = self.create_replacement_material( material, model )
              repairs[ material ] = replacement
            end
            e.send( setter[key], replacement )
          else
            e.send( setter[key], nil )
          end
        end
      }
    } # each entity
  end
  
  
  # Create new replacement material
  def self.create_replacement_material( material, model )
    new_material = model.materials.add( material.name )
    new_material.color = material.color
    new_material.alpha = material.alpha
    if material.texture
      if File.exist?( material.texture.filename )
        new_material.texture = material.texture.filename
      else
        filename = File.basename( material.texture.filename )
        temp_file = File.join( TT::System.temp_path, 'CleanUp', filename )
        temp_group = model.entities.add_group
        temp_group.material = material
        tw = Sketchup.create_texture_writer
        tw.load( temp_group )
        tw.write( temp_group, temp_file )
        new_material.texture = temp_file
        File.delete( temp_file )
        temp_group.erase!
      end
      new_material.texture.size = [ material.texture.width, material.texture.height ]
    end
    new_material
  end
  
  
  # Occationally some SketchUp models have multiple component definitions with
  # the same name. This is a bug which is not caught by SketchUp's own validation
  # process and can cause problems for plugins.
  # Checks the component names for duplicate names and ensures only unique names.
  def self.fix_component_names
    Sketchup.status_text = "Looking for multiple components of the same name..."
    
    model = Sketchup.active_model
    progress = TT::Progressbar.new( model.definitions, 'Looking for duplicate component names' )
    c = 0
    d = nil # Init variables for speed
    for definition in model.definitions
      progress.next
      copies = model.definitions.select { |d|
        d != definition && d.name == definition.name
      }
      next if copies.empty?
      puts "> Multiple definitions for '#{definition.name}' found!"
      for copy in copies
        puts "  > Renaming '#{copy.name}' to '#{model.definitions.unique_name(copy.name)}'..."
        copy.name = model.definitions.unique_name(copy.name)
        c += 1
      end
    end
    c
  end
  
  
  ### DEBUG ### ------------------------------------------------------------
  
  def self.reload
    TT::Lib.reload
    load __FILE__
  end

end # module

#-----------------------------------------------------------------------------

file_loaded( __FILE__ )

#-----------------------------------------------------------------------------