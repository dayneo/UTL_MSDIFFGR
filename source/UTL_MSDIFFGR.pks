CREATE OR REPLACE package utl_msdiffgr as

	subtype DIFFGRAM is DBMS_XMLDOM.DOMNode;
	subtype ROWLIST  is DBMS_XMLDOM.DOMNodeList;
	subtype DATAROW  is DBMS_XMLDOM.DOMNode;

	ROWSTATE_DETATCHED constant pls_integer := 1;
	ROWSTATE_UNCHANGED constant pls_integer := 2;
	ROWSTATE_ADDED     constant pls_integer := 4;
	ROWSTATE_DELETED   constant pls_integer := 8;
	ROWSTATE_MODIFIED  constant pls_integer := 16;

	procedure create_diffgram(p_diffgr out DIFFGRAM);
	procedure parse_diffgram(p_xml in clob, p_diffgr out DIFFGRAM);
	procedure parse_diffgram(p_xml in XMLDOM.DOMNode, p_diffgr out DIFFGRAM);

	function is_null(p_diffgr in DIFFGRAM) return boolean;

	-- Method:      FILL_TABLE(by sys_refcursor or by DBMS_SQL cursor)
	-- Description: Adds rows from the given refcursor to the diffgram.
	procedure fill_table(p_diffgr in DIFFGRAM, p_tablename in varchar2, p_refcur in sys_refcursor);
	procedure fill_table(p_diffgr in DIFFGRAM, p_tablename in varchar2, p_refcur in pls_integer);

	-- ROWSET METHODS
	function  get_length(p_rows in rowlist) return pls_integer;
	procedure get_row(p_rows in ROWLIST, p_index in pls_integer, p_row out DATAROW);
	-- RELATIONAL METHODS
	procedure get_parent_row(p_row in DATAROW, p_parent out DATAROW);

	-- GET/SET VALUES
	procedure get_value(p_row in DATAROW, p_column_name in varchar2, p_value out varchar2);
	procedure get_value(p_row in DATAROW, p_column_name in varchar2, p_value out number);
	procedure get_value(p_row in DATAROW, p_column_name in varchar2, p_value out date);
	procedure set_value(p_row in DATAROW, p_column_name in varchar2, p_value in varchar2);
	procedure set_value(p_row in DATAROW, p_column_name in varchar2, p_value in number);
	procedure set_value(p_row in DATAROW, p_column_name in varchar2, p_value in date);

	-- GET_CHANGES
	procedure get_changes(p_diffgr in DIFFGRAM, p_rows out ROWLIST);
	procedure get_changes(p_diffgr in DIFFGRAM, p_rowstates in pls_integer, p_rows out ROWLIST);
	procedure get_changes(p_diffgr in DIFFGRAM, p_tablename in varchar2, p_rows out ROWLIST);
	procedure get_changes(p_diffgr in DIFFGRAM, p_tablename in varchar2, p_rowstates in pls_integer, p_rows out ROWLIST);
	-- ACCEPT_CHANGES
	procedure accept_changes(p_diffgr in DIFFGRAM);
	procedure accept_changes(p_diffgr in DIFFGRAM, p_tablename in varchar2);
	procedure accept_changes(p_row in DATAROW);
	-- TODO: REJECT_CHANGES
	procedure write_to_clob(p_diffgr in diffgram, p_clob in out nocopy clob);

end utl_msdiffgr;
/

Show errors;
