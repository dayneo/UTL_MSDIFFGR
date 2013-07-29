CREATE OR REPLACE package body utl_msdiffgr as

	DIFFGRAM_URI        constant varchar2(1024)  := 'urn:schemas-microsoft-com:xml-diffgram-v1';
	DIFFGRAM_NAMESPACE  constant varchar2(1024)  := 'xmlns:diffgr="urn:schemas-microsoft-com:xml-diffgram-v1"';
	m_diffgram_template constant varchar2(32767) := '<?xml version="1.0" encoding="utf-8" ?><diffgr:diffgram xmlns:diffgr="urn:schemas-microsoft-com:xml-diffgram-v1"><DataInstance/><diffgr:before/></diffgr:diffgram>';

	procedure create_diffgram(p_diffgr out DIFFGRAM) is

		l_parser XMLParser.parser;
		l_diffgr XMLDom.DOMDocument;

	begin

		l_parser := XMLParser.newParser();
		
		begin
		
			XMLParser.parseClob(l_parser, m_diffgram_template);
			l_diffgr := XMLParser.getDocument(l_parser);
			XMLParser.freeParser(l_parser);
		
		exception
			when OTHERS then
				XMLParser.freeParser(l_parser);
				raise;
		end;

		p_diffgr := XMLDOM.makeNode(XMLDOM.GetDocumentElement(l_diffgr));

		utl_trace.f('Diffgram created'); -- did not output data due to large overhead it may have
		--utl_trace.f('Diffgram created', p_data=>XMLDOM.getXMLType(l_diffgr));

	end create_diffgram;

	procedure parse_diffgram(p_xml in clob, p_diffgr out DIFFGRAM) is

		l_parser XMLParser.parser;
		l_diffgr XMLDom.DOMDocument;

	begin

		utl_trace.f('Attempt to parse xml clob', p_data=>p_xml);

		l_parser := XMLParser.newParser();
		
		begin
		
			XMLParser.parseClob(l_parser, p_xml);
			l_diffgr := XMLParser.getDocument(l_parser);
			XMLParser.freeParser(l_parser);
		
		exception
			when OTHERS then
				XMLParser.freeParser(l_parser);
				raise;
		end;

		p_diffgr := XMLDOM.makeNode(l_diffgr);

	end parse_diffgram;

	procedure parse_diffgram(p_xml in XMLDOM.DOMNode, p_diffgr out DIFFGRAM) is

		l_name varchar2(32767);
		l_ns   varchar2(32767);

	begin

		xmldom.getlocalname(p_xml, l_name);
		xmldom.getnamespace(p_xml, l_ns); 
		utl_trace.f('Parsing domnode (%s of %s)', l_name, l_ns); 

		if l_name != 'diffgram' or l_ns != DIFFGRAM_URI then

			raise_application_error(-20000, 'Invalid diffgram node "' || l_name || '" (namespace "' || l_ns || '").');

		end if;

		p_diffgr := p_xml;

	end parse_diffgram;

	function is_null(p_diffgr in DIFFGRAM) return boolean is
	begin

		return dbms_xmldom.isnull(p_diffgr);

	end is_null;

	procedure gen_rowset(p_refcur in sys_refcursor, p_tablename in varchar2, p_rowset out XMLDom.DOMNode) is

		l_ctx    dbms_xmlgen.ctxhandle;
		l_xml    clob;
		l_parser xmlparser.parser;
		l_rowset xmldom.domdocument;
		l_rs     xmldom.domnode;

	begin

		l_ctx := dbms_xmlgen.newcontext(p_refcur);
		begin
			dbms_xmlgen.setNullHandling(l_ctx, dbms_xmlgen.DROP_NULLS);
			dbms_xmlgen.setRowTag(l_ctx, p_tablename);
      	l_xml := dbms_xmlgen.getxml(l_ctx);
      	dbms_xmlgen.closecontext(l_ctx);
		exception
			when OTHERS then
				dbms_xmlgen.closecontext(l_ctx);
				raise;
		end;

		if l_xml is null then
			l_xml := '<ROWSET />';
		end if;

		l_parser := xmlparser.newparser();
		begin
			xmlparser.parseclob(l_parser, l_xml);
			l_rowset := xmlparser.getdocument(l_parser);
			xmlparser.freeparser(l_parser);
		exception
			when OTHERS then
				xmlparser.freeparser(l_parser);
				raise;
		end;

		l_rs     := xslprocessor.selectsinglenode(xmldom.makenode(l_rowset), '/ROWSET');
		p_rowset := l_rs;

	end gen_rowset;

	procedure fill_table(p_diffgr in diffgram, p_tablename in varchar2, p_refcur in sys_refcursor) is

		l_rs     xmldom.domnode;
		l_ndlst  xmldom.domnodelist;
		l_cnt    pls_integer;
		l_n      xmldom.domnode;

		l_diffdoc xmldom.domdocument;
		l_data   xmldom.domnode;

		l_parent XMLDom.DOMNode;
		l_childtbl varchar2(32767);
		l_childlst xmldom.domnodelist;
		l_childcnt pls_integer;
		l_childn XMLDom.DOMNode;
		l_childe XMLDom.DOMElement;
		l_collst XMLDom.DOMNodeList;
		l_coln   XMLDom.DOMNode;
		l_colcnt pls_integer;
		
	begin

		l_diffdoc := xmldom.getownerdocument(p_diffgr);
		l_data    := xslprocessor.selectSingleNode(p_diffgr, '*', DIFFGRAM_NAMESPACE);

		gen_rowset(p_refcur, p_tablename, l_rs);

		l_ndlst := xslprocessor.selectNodes(l_rs, p_tablename);
		l_cnt   := xmldom.getLength(l_ndlst) - 1; 
		for i in 0..l_cnt loop
			l_n := xmldom.item(l_ndlst, i);
			l_n := xmldom.importNode(l_diffdoc, l_n, true);
			l_n := xmldom.appendChild(l_data, l_n);
			--l_id := p_tablename || i;
			xmldom.setattribute(xmldom.makeelement(l_n), 'diffgr:id', sys_guid(), DIFFGRAM_URI);
		end loop;

		-- Correct the sub items to conform to the diffgram
		l_ndlst := xslprocessor.selectNodes(l_data, 'descendant::*[*[name() = concat(name(parent::*), "_ROW")]]');
		l_cnt   := xmldom.getLength(l_ndlst) - 1;
		for i in 0..l_cnt loop
			l_n := xmldom.item(l_ndlst, i);
			xmldom.getLocalName(l_n, l_childtbl);
			l_parent   := xmldom.getParentNode(l_n);
			l_childlst := xmldom.getChildNodes(l_n);
			l_childcnt := xmldom.getLength(l_childlst) - 1;
			for childi in 0..l_childcnt loop
				-- append child rows
				l_childn := xmldom.item(l_childlst, childi);
				l_collst := xmldom.getChildNodes(l_childn);
				l_colcnt := xmldom.getLength(l_collst) - 1;
				l_childe := xmldom.createElement(l_diffdoc, l_childtbl);
				l_childn := xmldom.makeNode(l_childe);
				for coli in 0..l_colcnt loop
					-- append columns
					l_coln := xmldom.item(l_collst, coli);
					l_coln := xmldom.appendChild(l_childn, l_coln);
				end loop;
				xmldom.setattribute(xmldom.makeelement(l_childn), 'diffgr:id', sys_guid(), DIFFGRAM_URI);
				l_childn := xmldom.appendChild(l_parent, l_childn);
			end loop;
			-- remove old group node
			l_n := xmldom.removeChild(l_parent, l_n);
		end loop;

		l_ndlst := xslprocessor.selectNodes(l_data, 'descendant::*[@diffgr:id]/*[not(node())]', DIFFGRAM_NAMESPACE);
		l_cnt   := xmldom.getLength(l_ndlst) - 1;
		for i in 0..l_cnt loop

			l_n := xmldom.item(l_ndlst, i);
			l_parent := xmldom.getParentNode(l_n);
			l_n := xmldom.removeChild(l_parent, l_n);

		end loop;

	end fill_table;

	procedure fill_table(p_diffgr in diffgram, p_tablename in varchar2, p_refcur in pls_integer) is

		VARCHAR2_COLTYPE constant pls_integer := 1;
		NUMBER_COLTYPE   constant pls_integer := 2;
		DATE_COLTYPE     constant pls_integer := 12;

		l_diffdoc  xmldom.domdocument;
		l_data     xmldom.domnode;

		l_row_idx  pls_integer;
		l_row_id   varchar2(32767);

		l_col_cnt  pls_integer;
		l_col_desc DBMS_SQL.DESC_TAB2;

		l_row_elm  DBMS_XMLDOM.DOMElement;
		l_row_nd   DBMS_XMLDOM.DOMNode;

		l_col_elm  DBMS_XMLDOM.DOMElement;
		l_col_nd   DBMS_XMLDOM.DOMNode;
		l_val_txt  DBMS_XMLDOM.DOMText;
		l_val_nd   DBMS_XMLDOM.DOMNode;

		l_col_value   varchar2(32767);
		l_vchar_value varchar2(32767);
		l_num_value   number;
		l_date_value  date;

	begin

		l_diffdoc := xmldom.getownerdocument(p_diffgr);
		l_data    := xslprocessor.selectsinglenode(p_diffgr, '//DataInstance', DIFFGRAM_NAMESPACE);

		DBMS_SQL.DESCRIBE_COLUMNS2(p_refcur, l_col_cnt, l_col_desc);

		-- Add row nodes
		l_row_idx := 0;
		while DBMS_SQL.FETCH_ROWS(p_refcur) > 0 loop

			l_row_elm := DBMS_XMLDOM.CreateElement(l_diffdoc, p_tablename);
			l_row_nd  := DBMS_XMLDOM.MakeNode(l_row_elm);

			l_row_id  := p_tablename || l_row_idx;
			DBMS_XMLDOM.SetAttribute(l_row_elm, 'diffgr:id', l_row_id, DIFFGRAM_NAMESPACE);

			-- Add column nodes
			for i in 1..l_col_cnt loop

				l_col_elm := DBMS_XMLDOM.CreateElement(l_diffdoc, l_col_desc(i).col_name);
				l_col_nd  := DBMS_XMLDOM.MakeNode(l_col_elm);

				-- TODO: Find all the various datatypes and handle them here
				case l_col_desc(i).col_type
					when VARCHAR2_COLTYPE then

						DBMS_SQL.COLUMN_VALUE(p_refcur, i, l_vchar_value);
						l_col_value := l_vchar_value;

					when NUMBER_COLTYPE then

						DBMS_SQL.COLUMN_VALUE(p_refcur, i, l_num_value);
						l_col_value := l_num_value;

					when DATE_COLTYPE then

						DBMS_SQL.COLUMN_VALUE(p_refcur, i, l_date_value);
						l_col_value := l_date_value;

					else

						raise_application_error(-20000, 'Unknown column type found for column "' || l_col_desc(i).col_name || '"');

				end case;

				if l_col_value is not null then

					l_val_txt := DBMS_XMLDOM.CreateTextNode(l_diffdoc, l_col_value);
					l_val_nd  := DBMS_XMLDOM.MakeNode(l_val_txt);
					l_val_nd  := DBMS_XMLDOM.AppendChild(l_col_nd, l_val_nd);

				end if;

				l_col_nd  := DBMS_XMLDOM.AppendChild(l_row_nd, l_col_nd);

			end loop;

			l_row_nd := DBMS_XMLDOM.AppendChild(l_data, l_row_nd); -- TODO: Investigate performance of append after children appended

			l_row_idx := l_row_idx + 1;

		end loop;

		utl_trace.f('%s rows added to table %s.', l_row_idx, p_tablename);

	end fill_table;

	procedure get_changes(p_diffgr in diffgram, p_tablename in varchar2, p_rowstates in pls_integer, p_rows out rowlist) is 

		l_ndlst xmldom.domnodelist;
		l_xpath varchar2(32767);

	begin

		if bitand(p_rowstates, ROWSTATE_ADDED) = ROWSTATE_ADDED then

			l_xpath := l_xpath || '|*/descendant::' || p_tablename || '[@diffgr:hasChanges = "inserted"]';

		end if;

		if bitand(p_rowstates, ROWSTATE_MODIFIED) = ROWSTATE_MODIFIED then

			l_xpath := l_xpath || '|*/descendant::' || p_tablename || '[@diffgr:hasChanges = "modified"]';

		end if;

		if bitand(p_rowstates, ROWSTATE_DELETED) = ROWSTATE_DELETED then

			l_xpath := l_xpath || '|diffgr:before/descendant::' 
			                   || p_tablename 
			                   || '[not(@diffgr:id = ancestor::diffgr:diffgram/*[name()!="diffgr:before"][1]/descendant::*/@diffgr:id)]';

		end if;

		l_xpath := ltrim(l_xpath, '|');
		l_ndlst := xslprocessor.selectNodes(p_diffgr, l_xpath, DIFFGRAM_NAMESPACE);
		p_rows  := l_ndlst;

		utl_trace.f('%s rows selected; xpath=%s', XMLDOM.getLength(l_ndlst), l_xpath);

	end get_changes;

	procedure get_changes(p_diffgr in diffgram, p_tablename in varchar2, p_rows out rowlist) is

		l_rowstates pls_integer;

	begin

		l_rowstates := ROWSTATE_ADDED + ROWSTATE_MODIFIED + ROWSTATE_DELETED;
		get_changes(p_diffgr, p_tablename, l_rowstates, p_rows);

	end get_changes;

	procedure get_changes(p_diffgr in diffgram, p_rowstates in pls_integer, p_rows out rowlist) is

		l_xpath varchar2(32767);

	begin

		if bitand(p_rowstates, ROWSTATE_ADDED) = ROWSTATE_ADDED then

			l_xpath := l_xpath || '|*/descendant::*[@diffgr:hasChanges = "inserted"]';

		end if;

		if bitand(p_rowstates, ROWSTATE_MODIFIED) = ROWSTATE_MODIFIED then

			l_xpath := l_xpath || '|*/descendant::*[@diffgr:hasChanges = "modified"]';

		end if;

		if bitand(p_rowstates, ROWSTATE_DELETED) = ROWSTATE_DELETED then

			l_xpath := l_xpath || '|diffgr:before/descendant::*' 
			                   || '[not(@diffgr:id = ancestor::diffgr:diffgram/*[name()!="diffgr:before"][1]/descendant::*/@diffgr:id)]';

		end if;

		l_xpath := ltrim(l_xpath, '|');
		p_rows  := xslprocessor.selectNodes(p_diffgr, l_xpath, DIFFGRAM_NAMESPACE);

		utl_trace.f('%s rows selected; xpath=%s', XMLDOM.getLength(p_rows), l_xpath);

	end get_changes;

	procedure get_changes(p_diffgr in diffgram, p_rows out rowlist) is

		l_rowstates pls_integer;

	begin

		l_rowstates := ROWSTATE_ADDED + ROWSTATE_MODIFIED + ROWSTATE_DELETED;
		get_changes(p_diffgr, l_rowstates, p_rows);

	end get_changes;

	function get_length(p_rows in ROWLIST) return pls_integer is
	begin

		return XMLDom.getLength(p_rows);

	end get_length;

	procedure get_row(p_rows in ROWLIST, p_index in pls_integer, p_row out DATAROW) is
	begin

		p_row := XMLDOM.item(p_rows, p_index);

	end get_row;

	procedure get_parent_row(p_row in DATAROW, p_parent out DATAROW) is
	begin

		p_parent := xslprocessor.selectSingleNode(p_row, 'ancestor::*[@diffgr:id]', DIFFGRAM_NAMESPACE);		

	end get_parent_row;

	function get_node_value(p_context in XMLDom.DOMNode, p_xpath in varchar2 default '.', p_namespace in varchar2 default null) return varchar2 is
	
		l_value_nd XMLDom.DOMNode;
		
	begin
	
		l_value_nd := XSLProcessor.selectSingleNode(p_context, p_xpath, p_namespace);
		
		if XMLDom.isNull(l_value_nd) then
		
			return null;
		
		else
		
			if XMLDom.getNodeType(l_value_nd) = XMLDom.ELEMENT_NODE then
			
				l_value_nd := XMLDom.getFirstChild(l_value_nd);
			
			end if;
			
			return XMLDom.getNodeValue(l_value_nd);
		
		end if;
	
	end get_node_value;

	procedure get_value(p_row in DATAROW, p_column_name in varchar2, p_value out varchar2) is
	begin

		p_value := get_node_value(p_row, p_column_name);

	end get_value;

	procedure get_value(p_row in DATAROW, p_column_name in varchar2, p_value out number) is

		l_value varchar2(32767);

	begin

		l_value := get_node_value(p_row, p_column_name);
		p_value := to_number(l_value);

	end get_value;

	procedure get_value(p_row in DATAROW, p_column_name in varchar2, p_value out date) is

		l_value varchar2(32767);

	begin

		l_value := get_node_value(p_row, p_column_name);
		p_value := to_date(l_value);

	end get_value;

	function build_to_node(p_context in XMLDom.DOMNode, p_xpath in varchar2, p_namespace in varchar2) return XMLDom.DOMNode is
	
		l_doc             XMLDom.DOMDocument;
		l_node            XMLDom.DOMNode;
		l_xpath           varchar2(4000);
		l_node_name       varchar2(4000);
		l_parent_node     XMLDom.DOMNode;
		l_element         XMLDom.DOMElement;
		
	begin
	
		l_node := p_context;
	
		-- if p_xpath is null or ., then the context node is the node
		if (p_xpath is not null) and (p_xpath != '.') then
		
			l_xpath := p_xpath;
			l_node := XSLProcessor.selectSingleNode(p_context, l_xpath, p_namespace);
						
			-- if the node is not found, then it needs to be built
			if XMLDom.isNull(l_node) then
			
				l_node_name := regexp_substr(l_xpath, '[a-zA-Z_:-]+$');
				l_xpath := regexp_replace(l_xpath, l_node_name || '$', '');
				l_xpath := regexp_replace(l_xpath, '\/$', '');
				
				-- recursive call in order to get the parent node
				l_parent_node := build_to_node(p_context, l_xpath, p_namespace);
				
				-- append the newly created node
				l_doc := XMLDom.getOwnerDocument(p_context);
				-- TODO: Parse the element name to check for namespace. If so, then create it 
				--       with it's given namespace
				-- l_element := XMLDom.createElement(l_doc, l_node_name, p_namespace);
				l_element := XMLDom.createElement(l_doc, l_node_name);
				l_node := XMLDom.makeNode(l_element);
				l_node := XMLDom.appendChild(l_parent_node, l_node);
			
			end if;
		
		end if;
		
		return l_node;
		
	end build_to_node;

	procedure set_value(p_row in DATAROW, p_column_name in varchar2, p_value in varchar2) is

		l_xpath           varchar2(32767);
	
		l_node            XMLDom.DOMNode;
		l_textNode        XMLDom.DOMText;
		l_owner           XMLDom.DOMDocument;
		l_tmpNode         XMLDom.DOMNode;
		
	begin

		l_xpath := p_column_name;

		-- get or create the node
		l_node := build_to_node(p_row, l_xpath, null);
		
		--
		-- If the node is an element node, then get a handle on it's
		-- child text node.
		--
		if XMLDom.getNodeType(l_node) = XMLDom.ELEMENT_NODE then

			l_tmpNode := XMLDom.getFirstChild(l_node);
			
			if XMLDom.isNull(l_tmpNode) then
			
				--
				-- Create a text node
				--
				l_owner    := XMLDom.getOwnerDocument(p_row);
				l_textNode := XMLDom.createTextNode(l_owner, '');
				l_node     := XMLDom.appendChild(l_node, XMLDom.makeNode(l_textNode));
			
			else
			
				l_node := l_tmpNode;
				
			end if;
			
		end if;
		
		XMLDom.setNodeValue(l_node, p_value);

	end set_value;

	procedure set_value(p_row in DATAROW, p_column_name in varchar2, p_value in number) is

		l_value varchar2(32767);

	begin

		l_value := to_char(p_value);
		set_value(p_row, p_column_name, l_value);

	end set_value;

	procedure set_value(p_row in DATAROW, p_column_name in varchar2, p_value in date) is

		l_value varchar2(32767);

	begin

		l_value := to_char(p_value, 'yyyy-mm-dd"T"hh24:mi:ss');
		set_value(p_row, p_column_name, l_value);

	end set_value;

	--
	-- Determine if the given row was inserted
	--
	function is_insert(p_row in DATAROW) return boolean is

		l_xpath       varchar2(32767) := '@diffgr:hasChanges';
		l_ns          varchar2(32767) := DIFFGRAM_NAMESPACE;
		l_value       varchar2(32767);

	begin

		l_value := get_node_value(p_row, l_xpath, l_ns);		
		if l_value = 'inserted' then

			return true;

		else

			return false;

		end if;

	end is_insert;

	function is_update(p_row in DATAROW) return boolean is

		l_xpath       varchar2(32767) := '@diffgr:hasChanges';
		l_ns          varchar2(32767) := DIFFGRAM_NAMESPACE;
		l_value       varchar2(32767);

	begin

		l_value := get_node_value(p_row, l_xpath, l_ns);		
		if l_value = 'modified' then

			return true;

		else

			return false;

		end if;

	end is_update;

	--
	-- Determine if the given row was deleted
	--
	function is_delete(p_row in DATAROW) return boolean is

		l_xpath       varchar2(32767) := 'ancestor::diffgr:diffgram/*/descendant::*[@diffgr:id="%s"]';
		l_ns          varchar2(32767) := DIFFGRAM_NAMESPACE;
		l_id          varchar2(32767);
		l_node        XMLDom.DOMNode;

	begin

		l_id   := get_node_value(p_row, '@diffgr:id', l_ns);
		l_node := dbms_xslprocessor.selectSingleNode(p_row, replace(l_xpath, '%s', l_id), l_ns);

		if XMLDom.isNull(l_node) then

			return true;

		else

			return false;

		end if;

	end is_delete;

	procedure get_original_row(p_current_row in DATAROW, p_original_row out DATAROW) is

		l_current_row XMLDom.DOMNode;
		l_row_aselem  XMLDom.DOMElement;
		l_xpath       varchar2(32767) := 'descendant::*[@diffgr:id="%s"]';
		l_ns          varchar2(32767) := DIFFGRAM_NAMESPACE;
		l_diffgr      XMLDom.DOMNode;
		l_before      XMLDom.DOMNode;
		l_id          varchar2(32767);

	begin

		l_current_row := p_current_row;
	
		if is_insert(l_current_row) then

			p_original_row := null;

		elsif is_update(l_current_row) then

			l_id := get_node_value(l_current_row, '@diffgr:id', l_ns);
			l_diffgr := dbms_xslprocessor.selectSingleNode(l_current_row, 'ancestor::diffgr:diffgram', l_ns);
			l_before := dbms_xslprocessor.selectSingleNode(l_diffgr, 'diffgr:before', l_ns);
			p_original_row := dbms_xslprocessor.selectSingleNode(l_before, replace(l_xpath, '%s', l_id), l_ns);

		elsif is_delete(l_current_row) then

			p_original_row := l_current_row;

		end if;
		
	end get_original_row;

	procedure accept_insert(p_row in DATAROW) is

		l_ns varchar2(32767) := DIFFGRAM_NAMESPACE;

		l_node            XMLDom.DOMNode;
		l_xpath           varchar2(4000);
		l_node_name       varchar2(4000);
		l_parent_node     XMLDom.DOMNode;
		l_element         XMLDom.DOMElement;
		
	begin
	
		l_node := XSLProcessor.selectSingleNode(p_row, '@diffgr:hasChanges', l_ns);
		l_node := XMLDom.removeChild(p_row, l_node);

	end accept_insert;

	procedure accept_update(p_row in DATAROW) is

		l_ns varchar2(32767) := DIFFGRAM_NAMESPACE;

		l_node            XMLDom.DOMNode;
		l_xpath           varchar2(4000);
		l_node_name       varchar2(4000);
		l_parent_node     XMLDom.DOMNode;
		l_element         XMLDom.DOMElement;

		l_original_row    XMLDom.DOMNode;
		
	begin
	
		get_original_row(p_row, l_original_row);

		l_parent_node  := XMLDom.getParentNode(l_original_row);
		l_original_row := XMLDom.removeChild(l_parent_node, l_original_row);

		l_node := XSLProcessor.selectSingleNode(p_row, '@diffgr:hasChanges', l_ns);
		l_node := XMLDom.removeChild(p_row, l_node);

	end accept_update;

	procedure accept_delete(p_row in DATAROW) is

		l_parent_node     XMLDom.DOMNode;
		l_row             XMLDOM.DOMNode;

	begin
	
		l_parent_node := XMLDom.getParentNode(p_row);
		l_row := XMLDom.removeChild(l_parent_node, p_row);

	end accept_delete;

	procedure accept_changes(p_row in DATAROW) is
	begin

		if is_insert(p_row) then

			accept_insert(p_row);

		elsif is_update(p_row) then

			accept_update(p_row);

		elsif is_delete(p_row) then

			accept_delete(p_row);

		end if;

	end accept_changes;

	procedure accept_changes(p_diffgr in DIFFGRAM, p_tablename in varchar2) is

		l_changes ROWLIST;
		l_ubound  pls_integer;
		l_row     DATAROW;

	begin

		-- Do all insert, then all updates, then all deletes
		-- This improves performance because you will not 
		-- have to check the rowstate for each row returned.
		get_changes(p_diffgr, p_tablename, ROWSTATE_ADDED, l_changes);
		l_ubound  := get_length(l_changes);
		for i in 0..l_ubound loop

			get_row(l_changes, i, l_row);
			accept_insert(l_row);

		end loop;

		get_changes(p_diffgr, p_tablename, ROWSTATE_MODIFIED, l_changes);
		l_ubound  := get_length(l_changes);
		for i in 0..l_ubound loop

			get_row(l_changes, i, l_row);
			accept_update(l_row);

		end loop;

		get_changes(p_diffgr, p_tablename, ROWSTATE_DELETED, l_changes);
		l_ubound  := get_length(l_changes);
		for i in 0..l_ubound loop

			get_row(l_changes, i, l_row);
			accept_delete(l_row);

		end loop;

	end accept_changes;

	procedure accept_changes(p_diffgr in DIFFGRAM) is

		l_changes ROWLIST;
		l_ubound  pls_integer;
		l_row     DATAROW;

	begin

		-- Do all insert, then all updates, then all deletes
		-- This improves performance because you will not 
		-- have to check the rowstate for each row returned.
		get_changes(p_diffgr, ROWSTATE_ADDED, l_changes);
		l_ubound  := get_length(l_changes);
		for i in 0..l_ubound loop

			get_row(l_changes, i, l_row);
			accept_insert(l_row);

		end loop;

		get_changes(p_diffgr, ROWSTATE_MODIFIED, l_changes);
		l_ubound  := get_length(l_changes);
		for i in 0..l_ubound loop

			get_row(l_changes, i, l_row);
			accept_update(l_row);

		end loop;

		get_changes(p_diffgr, ROWSTATE_DELETED, l_changes);
		l_ubound  := get_length(l_changes);
		for i in 0..l_ubound loop

			get_row(l_changes, i, l_row);
			accept_delete(l_row);

		end loop;

	end accept_changes;


	procedure write_to_clob(p_diffgr in diffgram, p_clob in out nocopy clob) is
	begin

		if p_clob is null then

			dbms_lob.createTemporary(p_clob, true, dbms_lob.CALL);

		end if;

		xmldom.writetoclob(p_diffgr, p_clob);

	end write_to_clob;

end utl_msdiffgr;
/

show errors;
