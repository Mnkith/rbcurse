=begin
  * Name: table widget
  * Description: 
  * Author: rkumar (arunachalesha)
  
  --------
  * Date:   2008-12-27 21:33 
  * License:
    Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)

=end
require 'rubygems'
require 'ncurses'
require 'logger'
require 'lib/ver/ncurses'
require 'lib/ver/window'
require 'lib/rbcurse/rwidget'
require 'lib/rbcurse/table/tablecellrenderer'
require 'lib/rbcurse/checkboxcellrenderer'
require 'lib/rbcurse/listselectable'

include Ncurses
include RubyCurses
module RubyCurses
  extend self

  # ------ NOTE ------------------ #
  # Table contains a TableModel
  # Table contains a TableColumnModel (which contains TableColumn instances)
  # TableColumn contains 2 TableCellRenderer: column and header
  # ------------------------ #
  # 
  #
  # Due to not having method overloading, after usig new, use set_data or set_model
  #
  # This is a widget that displays tabular data. We will get into editing after this works out.
  # This uses the MVC architecture and is WIP as of 2009-01-04 18:37 
  # TODO cellrenderers should be able to get parents bgcolor and color (Jtables) if none defined for them.
  class Table < Widget
    include RubyCurses::EventHandler
    include RubyCurses::ListSelectable

    dsl_accessor :height
    dsl_accessor :title
    dsl_accessor :title_attrib
    dsl_accessor :selected_color, :selected_bgcolor, :selected_attr
    attr_accessor :current_index   # the row index universally
    #attr_accessor :current_column  # index of column (usually in current row )
    attr_reader :editing_column, :editing_row # TODO
    attr_accessor :is_editing # boolean

    def initialize form, config={}, &block
      super
      init_locals
    end

    def init_locals
      @col_offset = @row_offset = 1
      @focusable= true
      @current_index ||= 0
      @current_column ||= 0
      @current_column_offset ||= 0 # added 2009-01-12 19:06 current_column's offset
      @toprow ||= 0
      @to_print_borders ||= 1
      @show_grid ||= 1
      @curpos = 0
      # @selected_color ||= 'yellow'
      # @selected_bgcolor ||= 'black'
      @table_changed = true
      @repaint_required = true
    end

    def focussed_row
      @current_index
    end
    def focussed_col
      @current_column
    end
    # added 2009-01-07 13:05 so new scrollable can use
    def row_count
      @table_model.row_count
    end
    # added 2009-01-07 13:05 so new scrollable can use
    def scrollatrow
      @height -3
    end

    def set_data data, colnames_array
      if data.is_a? Array
        @table_model = RubyCurses::DefaultTableModel.new data, colnames_array
      elsif data.is_a? RubyCurses::TableModel
        table_model data
      end
      if colnames_array.is_a? Array
        @table_column_model = DefaultTableColumnModel.new colnames_array
      elsif colnames_array.is_a? RubyCurses::TableColumnModel
        table_column_model  colnames_array
      end
      create_default_list_selection_model
      create_table_header
    end
    def set_model tm, tcm=nil, lsm=nil
        table_model tm
        if tcm.nil?
          create_default_table_column_model
        else
          table_column_model tcm
        end
        if lsm.nil?
          create_default_list_selection_model
        else
          list_selection_model lsm
        end
      create_table_header
    end

    # getter and setter for table_model
    def table_model(*val)
      if val.empty?
        @table_model
      else
        raise "data error" if !val[0].is_a? RubyCurses::TableModel
        @table_model = val[0] 
      end
    end
    def table_column_model tcm
      raise "data error" if !tcm.is_a? RubyCurses::TableColumnModel
      @table_column_model = tcm
      @table_header.column_model(tcm) unless @table_header.nil?
    end
    def get_table_column_model
      @table_column_model 
    end
    # 
    def create_default_table_column_model
      table_column_model DefaultTableColumnModel.new
    end
    def create_table_header
      @table_header = TableHeader.new @table_column_model
    end

    #--- selection methods ---#
    def is_column_selected col
      raise "TODO "
    end
    def is_cell_selected row, col
      raise "TODO "
    end
    def add_column_selection_interval ix0, ix1
      raise "TODO "
      # if column_selection_allowed
    end
    def remove_column_selection_interval ix0, ix1
      raise "TODO "
    end



    def selected_column
      @table_column_model.selected_columns[0]
    end
    def selected_columns
      @table_column_model.selected_columns
    end
    def selected_column_count
      @table_column_model.selected_column_count
    end

    #--- row and column  methods ---#

    ##
    # getter and setter for current_column
    def current_column(*val)
      if val.empty?
        @current_column || 0
      else
        v = val[0]
        v = 0 if v < 0
        v = @table_column_model.column_count-1 if v > @table_column_model.column_count-1
        @current_column = v 
        set_form_col
      end
    end


    def add_column tc
      @table_column_model << tc
      table_structure_changed
    end
    def remove_column tc
      @table_column_model.remove_column  tc
      table_structure_changed
    end
    def get_column identifier
      ix = @table_column_model.column_index identifier
      return @table_column_model.column ix
    end
    def get_column_name ix
      @table_column_model.column(ix).identifier
    end
    def move_column ix, newix
      @table_column_model.move_column ix, newix
      table_structure_changed
    end

    #--- row and column  methods ---#
    def get_value_at row, col
      @table_model.get_value_at row, col
    end
    def set_value_at row, col, value
      @table_model.set_value_at row, col, value
    end

    #--- event listener support  methods (p521) ---#

    def table_changed tabmodev
    end
    def column_added tabcolmodev
    end
    def column_removed tabcolmodev
    end
    def column_moved tabcolmodev
    end
    ## to do for TrueClass and FalseClass
    def prepare_renderers
      @crh = Hash.new
      @crh['String'] = TableCellRenderer.new "", {"parent" => self }
      @crh['Fixnum'] = TableCellRenderer.new "", { "justify" => :right, "parent" => self}
      @crh['Float'] = TableCellRenderer.new "", {"justify" => :right, "parent" => self}
      @crh['TrueClass'] = CheckBoxCellRenderer.new "", {"parent" => self, "display_length"=>7}
      @crh['FalseClass'] = CheckBoxCellRenderer.new "", {"parent" => self, "display_length"=>7}
      #@crh['String'] = TableCellRenderer.new "", {"bgcolor" => "cyan", "color"=>"white", "parent" => self}
      #@crh['Fixnum'] = TableCellRenderer.new "", {"display_length" => 6, "justify" => :right, "color"=>"blue","bgcolor"=>"cyan" }
      #@crh['Float'] = TableCellRenderer.new "", {"display_length" => 6, "justify" => :right, "color"=>"blue", "bgcolor"=>"cyan" }
    end
    # this is vry temporary and will change as we begin to use models - i need to pick 
    # columns renderer
    def get_default_cell_renderer_for_class cname
      @crh || prepare_renderers
      @crh[cname] || @crh['String']
    end
    def set_default_cell_renderer_for_class cname, rend
      @crh ||= {}
      @crh[cname]=rend
    end
    ## override for cell or row behaviour
    def get_cell_renderer row, col
      # get columns renderer else class default
      column = @table_column_model.column(col)
      rend = column.cell_renderer
      return rend # can be nil
    end
    #
    # ------- editing methods---------- #
    def get_cell_editor row, col
    $log.debug " def get_cell_editor #{row}, #{col}"
      column = @table_column_model.column(col)
      editor = column.cell_editor
      return editor # can be nil
    end
    def edit_cell_at row, col
      editor = get_cell_editor row, col
      value = get_value_at row, col
      if editor.nil?
        cls = value.nil? ? get_value_at(0,col).class.to_s : value.class.to_s
        editor = get_default_cell_editor_for_class cls
        editor.component.display_length = @table_column_model.column(col).width
        editor.component.maxlen = editor.component.display_length if editor.component.respond_to? :maxlen
        $log.debug "EDIT_CELL_AT:  #{editor.component.display_length} = #{@table_column_model.column(col).width}"
      end
      $log.debug " got an EDITOR #{editor}"
      # by now we should have something to edit with. We just need to prepare the widgey.
      prepare_editor editor, row, col, value
    
    end
    def prepare_editor editor, row, col, value
      r,c = rowcol
      row = r + (row - @toprow) +1  #  @form.row , 1 added for header row!
      col = c+get_column_offset()
      editor.prepare_editor self, row, col, value
      @cell_editor = editor
      set_form_col 
    end
    def get_default_cell_editor_for_class cname
      @ceh ||= {}
      cname = 'Boolean' if cname == 'TrueClass' or cname == 'FalseClass'
      if @ceh.include? cname
        return @ceh[cname]
      else
        case cname
        when 'String'
          # I do not know cell width here, you will have toset display_length NOTE
          ce = RubyCurses::CellEditor.new RubyCurses::Field.new nil, {"focusable"=>false, "visible"=>false, "display_length"=> 8}
          @ceh['String'] = ce
          return ce
        when 'Fixnum'
          ce = RubyCurses::CellEditor.new RubyCurses::Field.new nil, {"focusable"=>false, "visible"=>false, "display_length"=> 5}
          @ceh[cname] = ce
          return ce
        when 'Float'
          ce = RubyCurses::CellEditor.new RubyCurses::Field.new nil, {"focusable"=>false, "visible"=>false, "display_length"=> 5}
          @ceh[cname] = ce
          return ce
        when "Boolean" #'TrueClass', 'FalseClass'
          ce = RubyCurses::CellEditor.new(RubyCurses::CheckBox.new nil, {"display_length"=> 0})
          @ceh[cname] = ce
          return ce
        else
          $log.debug " get_default_cell_editor_for_class UNKNOWN #{cname}"
          ce = RubyCurses::CellEditor.new RubyCurses::Field.new nil, {"focusable"=>false, "visible"=>false, "display_length"=> 6}
          @ceh[cname] = ce
          return ce
        end
      end
    end
    # returns true if editing is occurring
    #def is_editing?
    #  @editing
    #end
   
    # ----------------- #

    ##
    # key handling
    # make separate methods so callable programmatically
    def handle_key(ch)
      @current_index ||= 0
      @toprow ||= 0
      h = scrollatrow()
      rc = @table_model.row_count
      if @is_editing and (ch != 27 and ch != ?\C-c and ch != 13)
        $log.debug " sending ch #{ch} to cell editor"
        ret = @cell_editor.component.handle_key(ch)
        @repaint_required = true
        $log.debug "RET #{ret} got from to cell editor"
        return if ret != :UNHANDLED
      end
      case ch
      when KEY_UP  # show previous value
        previous_row
    #    @toprow = @current_index
      when KEY_DOWN  # show previous value
        next_row
      when 27, ?\C-c:
        @is_editing = false if @is_editing
      when KEY_ENTER, 10, 13:
        @is_editing = !@is_editing
        if @is_editing 
          $log.debug " turning on editing cell at #{focussed_row}, #{focussed_col}"
          edit_cell_at focussed_row(), focussed_col()
        else
          set_value_at(focussed_row(), focussed_col(), @cell_editor.getvalue) #.dup 2009-01-10 21:42 boolean can't duplicate
        end

      when ?\C-x #32:
        #add_row_selection_interval @current_index, @current_index
        toggle_row_selection @current_index #, @current_index
        @repaint_required = true
      when ?\C-n:
        scroll_forward
      when ?\C-p:
        scroll_backward
      when 48, ?\C-[:
        # please note that C-[ gives 27, same as esc so will respond after ages
        goto_top
      when ?\C-]:
        goto_bottom
      else
        ret = process_key ch, self
        return :UNHANDLED if ret == :UNHANDLED
      end
    end
    ##
    def previous_row
        @current_index -= 1 if @current_index > 0
        bounds_check
    end
    def next_row
      rc = row_count
      @current_index += 1 if @current_index < rc
      bounds_check
    end
    def goto_bottom
      rc = row_count
      @current_index = rc -1
      bounds_check
    end
    def goto_top
        @current_index = 0
        bounds_check
    end
    def scroll_backward
      h = scrollatrow()
      @current_index -= h 
      bounds_check
    end
    def scroll_forward
      h = scrollatrow()
      rc = row_count
      # more rows than box
      if h < rc
        @toprow += h+1 #if @current_index+h < rc
        @current_index = @toprow
      else
        # fewer rows than box
        @current_index = rc -1
      end
      #@current_index += h+1 #if @current_index+h < rc
      bounds_check
    end

    def bounds_check
      h = scrollatrow()
      rc = row_count
      #$log.debug " PRE CURR:#{@current_index}, TR: #{@toprow} RC: #{rc} H:#{h}"
      @current_index = 0 if @current_index < 0  # not lt 0
      @current_index = rc-1 if @current_index >= rc # not gt rowcount
      @toprow = rc-h-1 if rc > h and @toprow > rc - h - 1 # toprow shows full page if possible
      # curr has gone below table,  move toprow forward
      if @current_index - @toprow > h
        @toprow = @current_index - h
      elsif @current_index < @toprow
        # curr has gone above table,  move toprow up
        @toprow = @current_index
      end
      #$log.debug " POST CURR:#{@current_index}, TR: #{@toprow} RC: #{rc} H:#{h}"
      set_form_row
      @repaint_required = true
    end
    # the cursor should be appropriately positioned
    def on_enter
      set_form_row
    end
    def set_form_row
      r,c = rowcol
      # +1 is due to header
      @form.row = r + (@current_index-@toprow) + 1
    end
    # set cursor on correct column, widget
    def set_form_col col=@curpos
      @curpos = col
      @current_column_offset = get_column_offset
      @form.col = @col + @col_offset + @curpos + @current_column_offset
    end
    # protected
    def get_column_offset columnid=@current_column
      return @table_column_model.column(columnid).column_offset
    end


    # temporary, while testing and fleshing out
    def table_data_changed 
      $log.debug " TEMPORARILY PLACED. REMOVE AFTER FINALIZED. table_data_changed"
      #@data_changed = true
      @repaint_required = true
    end
    def table_structure_changed 
      $log.debug " TEMPORARILY PLACED. REMOVE AFTER FINALIZED. table_structure_changed"
      @table_changed = true
      @repaint_required = true
    end
    def repaint
      return unless @repaint_required
      print_border @form.window if @to_print_borders == 1 # do this once only, unless everything changes
      cc = @table_model.column_count
      rc = @table_model.row_count
      tcm = @table_column_model
      tm = @table_model
      tr = @toprow
      acolor = get_color $datacolor
      h = scrollatrow()
      r,c = rowcol
      # each cell should print itself, however there is a width issue. 
      # Then thee
      print_header # do this once, unless columns changed
      # TCM should give modelindex of col which is used to fetch data from TM
      r += 1 # save for header
      0.upto(h) do |hh|
        crow = tr+hh
        if crow < rc
          offset = 0
    #      0.upto(cc-1) do |colix|
          # we loop through column_model and fetch data based on model index
          tcm.each_with_index do |acolumn, colix|
            #acolumn = tcm.column(colix)
            model_index = acolumn.model_index
            focussed = @current_index == crow ? true : false 
            selected = is_row_selected crow
            content = tm.get_value_at(crow, model_index)
            #renderer = get_default_cell_renderer_for_class content.class.to_s
            renderer = get_cell_renderer(crow, colix)
            if renderer.nil?
              renderer = get_default_cell_renderer_for_class(content.class.to_s) if renderer.nil?
              renderer.display_length acolumn.width unless acolumn.nil?
            end
            width = renderer.display_length + 1
            #renderer.repaint @form.window, r+hh, c+(colix*11), content, focussed, selected
            acolumn.column_offset = offset
            renderer.repaint @form.window, r+hh, c+(offset), content, focussed, selected
            offset += width
          end
        else
          @form.window.printstring r+hh, c, " " * (@width-2), acolor,@attr
          # clear rows
        end
      end
      if @is_editing
        @cell_editor.component.repaint unless @cell_editor.nil? or @cell_editor.component.form.nil?
      end
      @table_changed = false
      @repaint_required = false
    end
    def print_border g
      return unless @table_changed
      g.print_border @row, @col, @height, @width, $datacolor
    end
    def print_header
      return unless @table_changed
      r,c = rowcol
      header_model = @table_header.table_column_model
      tcm = @table_column_model ## could have been overridden, should we use this at all
      offset = 0
      header_model.each_with_index do |tc, colix|
        acolumn = tcm.column colix
        renderer = tc.cell_renderer
        renderer = @table_header.default_renderer if renderer.nil?
        renderer.display_length acolumn.width unless acolumn.nil?
        width = renderer.display_length + 1
        content = tc.header_value
        renderer.repaint @form.window, r, c+(offset), content, false, false
        offset += width
      end
    end


    attr_accessor :toprow # top visible
  end # class Table

  ## TC 
  # All column changes take place in ColumnModel not in data. TC keeps pointer to col in data via
  # model_index
  class TableColumn
    attr_reader :identifier
    attr_accessor :min_width, :max_width, :is_resizable
    attr_accessor :cell_renderer
    attr_accessor :model_index  # index inside TableModel
    # user may override or set for this column, else headers default will be used
    attr_accessor :header_renderer  
    attr_reader :header_value
    ## added column_offset on 2009-01-12 19:01 
    attr_accessor :column_offset # where we've place this guy. in case we need to position cursor
    attr_accessor :cell_editor


    def initialize model_index, identifier, header_value, width, config={}, &block
      @width = width
      @model_index = model_index
      @identifier = identifier
      @header_value = header_value
      instance_eval &block if block_given?
    end
    ## display this row on top
    def width(*val)
      if val.empty?
        @width
      else
        @width = val[0] 
      # fire property change
      end
    end
    ## table header will be picking header_value from here
    def set_header_value w
      @header_value = w
      # fire property change
    end
  end # class tc

  ## TCM 
  #
  class TableColumnModel
    def column ix
      nil
    end
    def columns 
      nil
    end
    def column_count
      0
    end
    def column_selection_allowed
      false
    end
    def selected_column_count
      0
    end
    def selected_columns
      nil
    end
    def total_column_width
      0
    end
    def get_selection_model
      nil
    end
    def set_selection_model lsm
    end
    def add_column tc
    end
    def remove_column tc
    end
    def move_column ix, newix
    end
    def column_index identifier
      nil
    end
    # add tcm listener
  end
  ## DTCM  DCM
  class DefaultTableColumnModel < TableColumnModel
    include Enumerable
    attr_accessor :column_selection_allowed
    
    ##
    #  takes a column names array
    def initialize cols=[]
      @columns = []
      cols.each_with_index {|c, index| @columns << TableColumn.new(index, c, c, 10) }
      @selected_columns = []
    end
    def column ix
      raise "Invalid arg #{ix}" if ix < 0 or ix > (@columns.length() -1)
      @columns[ix]
    end
    ##
    # yields a table column
    def each
      @columns.each { |c| 
        yield c 
      }
    end
    def column_count
      @columns.length
    end
    def selected_column_count
      @selected_columns.length
    end
    def selected_columns
      @selected_columns
    end
    def clear_selection
      @selected_columns = []
    end
    def total_column_width
      0
    end
    def set_selection_model lsm
      @column_selection_model = lsm
    end
    def add_column tc
      @columns << tc
    end
    def remove_column tc
      @columns.delete  tc
    end
    def move_column ix, newix
      acol = remove_column column(ix)
      @columns.insert newix, acol
    end
    ##
    # return index of column identified with identifier
    def column_index identifier
      @columns.each_with_index {|c, i| return i if c.identifier == identifier }
      return nil
    end
    ## TODO  - if we get into column selection somewhen
    def get_selection_model
      @lsm
    end
    def set_selection_model lsm
      @lsm = lsm
    end
    # add tcm listener
  end

  ## TM 
    class TableModel
      def column_count
      end
      def row_count
      end
      def set_value_at row, col, val
      end
      def get_value_at row, col
      end
=begin
      def << obj
      end
      def insert row, obj
      end
      def delete obj
      end
      def delete_at row
      end
=end
    end # class 

    class DefaultTableModel
      def initialize data, colnames_array
        @data = data
        @column_identifiers = colnames_array
      end
      def column_count
        @column_identifiers.count
      end
      def row_count
        @data.length
      end
      def set_value_at row, col, val
          # if editing allowed
          @data[row][col] = val
      end
      def get_value_at row, col
        return @data[row][ col]
      end
      def << obj
        @data << obj
      end
      def insert row, obj
        @data.insert row, obj
      end
      def delete obj
        @data.delete obj
      end
      def delete_at row
        @data.delete_at row
      end
    end # class 

    ##
    # LSM 
    #
    class DefaultListSelectionModel
      include EventHandler
      attr_accessor :selection_mode
      attr_reader :anchor_selection_index
      attr_reader :lead_selection_index
      def initialize
        @selected_indices=[]
        @anchor_selection_index = -1
        @lead_selection_index = -1
        @selection_mode = :MULTIPLE
      end

      def clear_selection
        @selected_indices=[]
      end
      def is_selected_index ix
        @selected_indices.include? ix
      end
      def get_max_selection_index
        @selected_indices[-1]
      end
      def get_min_selection_index
        @selected_indices[0]
      end
      def get_selected_rows
        @selected_indices
      end
      ## TODO should go in sorted, and no dupes
      def add_selection_interval ix0, ix1
        @anchor_selection_index = ix0
        @lead_selection_index = ix1
        ix0.upto(ix1) {|i| @selected_indices  << i unless @selected_indices.include? i }
      end
      def remove_selection_interval ix0, ix1
        @anchor_selection_index = ix0
        @lead_selection_index = ix1
        @selected_indices.delete_if {|x| x >= ix0 and x <= ix1}
      end
      def insert_index_interval ix0, len
        @anchor_selection_index = ix0
        @lead_selection_index = ix0+len
        add_selection_interval @anchor_selection_index, @lead_selection_index
      end
    end # class DefaultListSelectionModel
    ##
    # 
    class TableHeader
      attr_accessor :default_renderer
      attr_accessor :table_column_model
      def initialize table_column_model
        @table_column_model = table_column_model
        create_default_renderer
      end
      def create_default_renderer
        #@default_renderer = TableCellRenderer.new "", {"display_length" => 10, "justify" => :center}
        @default_renderer = TableCellRenderer.new "", {"display_length" => 10, "justify" => :center, "color"=>"white", "bgcolor"=>"blue"}
      end

    end

end # module
