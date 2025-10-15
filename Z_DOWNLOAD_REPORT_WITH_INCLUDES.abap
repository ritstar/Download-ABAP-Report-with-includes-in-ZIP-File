*&---------------------------------------------------------------------*
*& Report Z_DOWNLOAD_REPORT_WITH_INCLUDES
*&---------------------------------------------------------------------*
*& Download report source code with all includes as separate files in ZIP
*&---------------------------------------------------------------------*
REPORT z_download_report_with_includes.

* Type declarations
TYPES: BEGIN OF ty_include,
         incname TYPE program,
       END OF ty_include.

TYPES: BEGIN OF ty_source,
         progname TYPE program,
         source   TYPE TABLE OF string WITH EMPTY KEY,
       END OF ty_source.

TYPES: tt_includes TYPE STANDARD TABLE OF ty_include WITH DEFAULT KEY.

* Data declarations
DATA: lt_includes      TYPE tt_includes,
      lt_all_sources   TYPE TABLE OF ty_source,
      ls_source        TYPE ty_source,
      lt_source_lines  TYPE TABLE OF string,
      lv_filename      TYPE string,
      lo_zip           TYPE REF TO cl_abap_zip,
      lv_xstring       TYPE xstring,
      lv_zip_xstring   TYPE xstring,
      lv_path          TYPE string,
      lv_fullpath      TYPE string,
      lv_user_action   TYPE i.

* Selection screen
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
PARAMETERS: p_reprt TYPE program OBLIGATORY.  " Report Name
SELECTION-SCREEN END OF BLOCK b1.

* F4 help for program selection
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_reprt.
  PERFORM f4_program_help.

START-OF-SELECTION.
  
  " Get main report and all includes
  PERFORM get_all_includes.
  
  " Read source code for all programs
  PERFORM read_all_sources.
  
  " Create ZIP file
  PERFORM create_zip_file.
  
  " Download ZIP file
  PERFORM download_zip.

END-OF-SELECTION.

*&---------------------------------------------------------------------*
*& Form f4_program_help
*&---------------------------------------------------------------------*
FORM f4_program_help.
  
  CALL FUNCTION 'REPOSITORY_INFO_SYSTEM_F4'
    EXPORTING
      object_type          = 'PROG'
      object_name          = p_reprt
      suppress_selection   = 'X'
    IMPORTING
      object_name_selected = p_reprt
    EXCEPTIONS
      cancel               = 0.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form get_all_includes
*&---------------------------------------------------------------------*
FORM get_all_includes.
  
  DATA: ls_include TYPE ty_include.

  " Add main program to list
  ls_include-incname = p_reprt.
  APPEND ls_include TO lt_includes.
  
  " Get all includes recursively
  PERFORM scan_for_includes USING p_reprt
                            CHANGING lt_includes.
  
  " Remove duplicates
  SORT lt_includes BY incname.
  DELETE ADJACENT DUPLICATES FROM lt_includes COMPARING incname.
  
  WRITE: / 'Total programs found:', sy-tfill.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form scan_for_includes
*&---------------------------------------------------------------------*
FORM scan_for_includes USING    iv_progname TYPE program
                       CHANGING ct_includes TYPE tt_includes.
  
  DATA: lt_code       TYPE TABLE OF string,
        lt_tokens     TYPE STANDARD TABLE OF stoken,
        lt_statements TYPE STANDARD TABLE OF sstmnt,
        lt_keywords   TYPE TABLE OF text20,
        lv_keyword    TYPE text20,
        ls_token      TYPE stoken,
        ls_include    TYPE ty_include,
        lv_nextline   TYPE i,
        lv_maxlines   TYPE i.

  " Read the program source
  READ REPORT iv_progname INTO lt_code.
  
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  " Prepare keywords to scan
  lv_keyword = 'INCLUDE'.
  APPEND lv_keyword TO lt_keywords.

  " Scan source code for INCLUDE statements
  SCAN ABAP-SOURCE lt_code
       TOKENS INTO lt_tokens
       WITH INCLUDES
       STATEMENTS INTO lt_statements
       KEYWORDS FROM lt_keywords.

  " Process tokens to find include names
  DESCRIBE TABLE lt_tokens LINES lv_maxlines.
  
  LOOP AT lt_tokens INTO ls_token WHERE str = 'INCLUDE' AND type = 'I'.
    lv_nextline = sy-tabix + 1.
    
    IF lv_nextline <= lv_maxlines.
      READ TABLE lt_tokens INDEX lv_nextline INTO ls_token.
      
      IF sy-subrc = 0.
        " Check if it's a valid include name (not STRUCTURE)
        IF ls_token-str <> 'STRUCTURE' AND 
           ls_token-str IS NOT INITIAL.
          
          ls_include-incname = ls_token-str.
          
          " Check if already processed
          READ TABLE ct_includes TRANSPORTING NO FIELDS
               WITH KEY incname = ls_include-incname.
          
          IF sy-subrc <> 0.
            APPEND ls_include TO ct_includes.
            
            " Recursive call for nested includes
            PERFORM scan_for_includes USING ls_include-incname
                                      CHANGING ct_includes.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form read_all_sources
*&---------------------------------------------------------------------*
FORM read_all_sources.
  
  DATA: ls_include TYPE ty_include,
        lt_code    TYPE TABLE OF string.

  LOOP AT lt_includes INTO ls_include.
    CLEAR: ls_source, lt_code.
    
    " Read source code
    READ REPORT ls_include-incname INTO lt_code.
    
    IF sy-subrc = 0.
      ls_source-progname = ls_include-incname.
      ls_source-source   = lt_code.
      APPEND ls_source TO lt_all_sources.
      
      WRITE: / 'Read source:', ls_include-incname.
    ELSE.
      WRITE: / 'Could not read:', ls_include-incname, '(might be SAP standard)'.
    ENDIF.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form create_zip_file
*&---------------------------------------------------------------------*
FORM create_zip_file.
  
  DATA: ls_source_data TYPE ty_source,
        lv_string      TYPE string,
        lv_line        TYPE string.

  " Create ZIP object
  CREATE OBJECT lo_zip.

  " Loop through all source codes
  LOOP AT lt_all_sources INTO ls_source_data.
    
    CLEAR: lv_string, lv_xstring.
    
    " Convert source lines to single string with line breaks
    LOOP AT ls_source_data-source INTO lv_line.
      CONCATENATE lv_string lv_line cl_abap_char_utilities=>cr_lf
           INTO lv_string.
    ENDLOOP.

    " Convert string to xstring
    CALL FUNCTION 'SCMS_STRING_TO_XSTRING'
      EXPORTING
        text   = lv_string
      IMPORTING
        buffer = lv_xstring
      EXCEPTIONS
        OTHERS = 1.

    IF sy-subrc = 0.
      " Create filename with .txt extension
      CONCATENATE ls_source_data-progname '.txt' INTO lv_filename.
      
      " Add file to ZIP
      lo_zip->add( EXPORTING
                     name    = lv_filename
                     content = lv_xstring ).
      
      WRITE: / 'Added to ZIP:', lv_filename.
    ENDIF.
  ENDLOOP.

  " Save ZIP content
  lv_zip_xstring = lo_zip->save( ).
  
  WRITE: / 'ZIP file created successfully.'.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form download_zip
*&---------------------------------------------------------------------*
FORM download_zip.
  
  DATA: lt_binary_tab TYPE TABLE OF x255,
        lv_length     TYPE i,
        lv_filename   TYPE string,
        lv_defname    TYPE string.

  " Prepare default filename
  CONCATENATE p_reprt '_includes.zip' INTO lv_defname.

  " File save dialog
  CALL METHOD cl_gui_frontend_services=>file_save_dialog
    EXPORTING
      default_extension    = 'zip'
      default_file_name    = lv_defname
      file_filter          = 'ZIP Files (*.zip)|*.zip|All Files (*.*)|*.*'
    CHANGING
      filename             = lv_filename
      path                 = lv_path
      fullpath             = lv_fullpath
      user_action          = lv_user_action
    EXCEPTIONS
      cntl_error           = 1
      error_no_gui         = 2
      not_supported_by_gui = 3
      OTHERS               = 4.

  IF sy-subrc <> 0 OR lv_user_action = cl_gui_frontend_services=>action_cancel.
    WRITE: / 'Download cancelled by user.'.
    RETURN.
  ENDIF.

  " Convert xstring to binary table
  CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
    EXPORTING
      buffer        = lv_zip_xstring
    IMPORTING
      output_length = lv_length
    TABLES
      binary_tab    = lt_binary_tab.

  " Download file
  CALL FUNCTION 'GUI_DOWNLOAD'
    EXPORTING
      bin_filesize = lv_length
      filename     = lv_fullpath
      filetype     = 'BIN'
    TABLES
      data_tab     = lt_binary_tab
    EXCEPTIONS
      OTHERS       = 1.

  IF sy-subrc = 0.
    WRITE: / 'ZIP file downloaded successfully to:', lv_fullpath.
    MESSAGE 'ZIP file downloaded successfully!' TYPE 'S'.
  ELSE.
    WRITE: / 'Error downloading ZIP file.'.
    MESSAGE 'Error downloading ZIP file.' TYPE 'E'.
  ENDIF.

ENDFORM.
