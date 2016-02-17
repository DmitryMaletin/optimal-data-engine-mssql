﻿
CREATE PROCEDURE [dbo].[dv_load_source_table_key_lookup]
(
  @vault_source_system_name             varchar(128) = NULL
, @vault_source_table_schema			varchar(128) = NULL
, @vault_source_table_name              varchar(128) = NULL
, @link_load_only						char(1) = 'N'  -- "Y" Indicates that this temp table is being used for a link load key lookup, not a Sat key Lookup.
, @vault_temp_table_name				varchar(116) OUTPUT
, @vault_sql_statement					nvarchar(max) OUTPUT
, @dogenerateerror                      bit		= 0
, @dothrowerror                         bit		= 1

)
AS
BEGIN
SET NOCOUNT ON

-- To Do - add Logging for the Payload Parameter
--         validate Parameters properly
--declare @sat_name varchar(100) =  'AdventureWorks2014_production_productinventory'

-- System Wide Defaults
-- Local Defaults Values
DECLARE @crlf											char(2) = CHAR(13) + CHAR(10)
-- Global Defaults
DECLARE
                 @def_global_lowdate                    datetime
				,@def_global_highdate                   datetime
				,@def_global_default_load_date_time     varchar(128)
                ,@def_global_failed_lookup_key          int
-- Hub Defaults
                ,@def_hub_schema                        varchar(128)
--Link Defaults
                ,@def_link_schema                       varchar(128)
--Sat Defaults
                ,@def_sat_prefix                        varchar(128)
                ,@def_sat_schema                        varchar(128)
                ,@def_sat_filegroup                     varchar(128)
                ,@sat_start_date_col                    varchar(128)
                ,@sat_end_date_col                      varchar(128)
				,@def_sat_IsColumnStore					int

-- Object Specific Settings
-- Source Table
                ,@source_system                         varchar(128)
				,@source_database                       varchar(128)
                ,@source_schema                         varchar(128)
                ,@source_table                          varchar(128)
                ,@source_table_config_key               int
                ,@source_qualified_name                 varchar(512)
                ,@source_load_date_time                 varchar(128)
                ,@source_payload                        nvarchar(max)
-- Hub Table
                ,@hub_database                          varchar(128)
                ,@hub_schema                            varchar(128)
                ,@hub_table                             varchar(128)
                ,@hub_surrogate_keyname                 varchar(128)
                ,@hub_config_key                        int
                ,@hub_qualified_name                    varchar(512)
 
-- Link Table
                ,@link_database                         varchar(128)
                ,@link_schema                           varchar(128)
                ,@link_table                            varchar(128)
                ,@link_surrogate_keyname                varchar(128)
                ,@link_config_key                       int
                ,@link_qualified_name                   varchar(512)
                ,@link_lookup_joins                     nvarchar(max)
                ,@link_hub_keys                         nvarchar(max)
-- Sat Table
                ,@sat_database                          varchar(128)
                ,@sat_schema                            varchar(128)
                ,@sat_table                             varchar(128)
                ,@sat_surrogate_keyname                 varchar(128)
                ,@sat_config_key                        int
                ,@sat_link_hub_flag                     char(1)
				,@sat_duplicate_removal_threshold		int
				,@sat_hashmatching_char_length          int
                ,@sat_qualified_name                    varchar(512)
                ,@sat_payload                           nvarchar(max)



--  Working Storage
DECLARE @sat_insert_count								int
       ,@temp_table_name_001							varchar(116)
       ,@sql											nvarchar(max)
       ,@sql1											nvarchar(max)
       ,@sql2											nvarchar(max)
       ,@surrogate_key_match							nvarchar(max)
DECLARE @declare										nvarchar(512)   = ''
DECLARE @count_rows										nvarchar(256)   = ''
DECLARE @match_list										nvarchar(max)   = ''
DECLARE @value_list										nvarchar(max)   = ''
DECLARE @sat_column_list								nvarchar(max)   = ''
DECLARE @hub_column_list								nvarchar(max)   = ''

DECLARE @ParmDefinition									nvarchar(500);


DECLARE @wrk_link_joins									nvarchar(max)
DECLARE @wrk_hub_joins									nvarchar(max)
DECLARE @wrk_link_keys									nvarchar(max)

-- Log4TSQL Journal Constants
DECLARE @SEVERITY_CRITICAL								smallint = 1;
DECLARE @SEVERITY_SEVERE								smallint = 2;
DECLARE @SEVERITY_MAJOR									smallint = 4;
DECLARE @SEVERITY_MODERATE								smallint = 8;
DECLARE @SEVERITY_MINOR									smallint = 16;
DECLARE @SEVERITY_CONCURRENCY							smallint = 32;
DECLARE @SEVERITY_INFORMATION							smallint = 256;
DECLARE @SEVERITY_SUCCESS								smallint = 512;
DECLARE @SEVERITY_DEBUG									smallint = 1024;
DECLARE @NEW_LINE										char(1)  = CHAR(10);

-- Log4TSQL Standard/ExceptionHandler variables
DECLARE	@_Error											int
      , @_RowCount										int
      , @_Step											varchar(128)
      , @_Message										nvarchar(512)
      , @_ErrorContext									nvarchar(512)

-- Log4TSQL JournalWriter variables
DECLARE			  @_FunctionName                        varchar(255)
                , @_SprocStartTime                      datetime
                , @_JournalOnOff                        varchar(3)
                , @_Severity                            smallint
                , @_ExceptionId                         int
                , @_StepStartTime                       datetime
                , @_ProgressText                        nvarchar(max)

SET @_Error             = 0;
SET @_FunctionName      = OBJECT_NAME(@@PROCID);
SET @_Severity          = @SEVERITY_INFORMATION;
SET @_SprocStartTime    = sysdatetimeoffset();
SET @_ProgressText      = ''
SET @_JournalOnOff      = log4.GetJournalControl(@_FunctionName, 'HOWTO');  -- left Group Name as HOWTO for now.

-- set Log4TSQL Parameters for Logging:
SET @_ProgressText              = @_FunctionName + ' starting at ' + CONVERT(char(23), @_SprocStartTime, 121) + ' with inputs: '
                                                 + @NEW_LINE + '    @vault_source_system_name  : ' + COALESCE(@vault_source_system_name, 'NULL')
                                                 + @NEW_LINE + '    @vault_source_table_schema : ' + COALESCE(@vault_source_table_schema, 'NULL')
                                                 + @NEW_LINE + '    @vault_source_table_name   : ' + COALESCE(@vault_source_table_name, 'NULL')
                                                 + @NEW_LINE + '    @link_load_only            : ' + COALESCE(@link_load_only, 'NULL')
                                                 + @NEW_LINE + '    @DoGenerateError           : ' + COALESCE(CAST(@DoGenerateError AS varchar), 'NULL')
                                                 + @NEW_LINE + '    @DoThrowError              : ' + COALESCE(CAST(@DoThrowError AS varchar), 'NULL')
                                                 + @NEW_LINE

BEGIN TRY
SET @_Step = 'Generate any required error';
IF @DoGenerateError = 1
   select 1 / 0
SET @_Step = 'Validate inputs';

--IF (select count(*) from [dbo].[dv_sat] where sat_name = @sat_name) <> 1
--                      RAISERROR('Invalid sat Name: %s', 16, 1, @sat_name);
--IF isnull(@recreate_flag, '') not in ('Y', 'N')
--                      RAISERROR('Valid values for recreate_flag are Y or N : %s', 16, 1, @recreate_flag);
/*--------------------------------------------------------------------------------------------------------------*/
SET @_Step = 'Get Defaults'
-- System Wide Defaults
select
-- Global Defaults
 @def_global_lowdate                            = cast([dbo].[fn_get_default_value] ('LowDate','Global')              as datetime)
,@def_global_highdate                           = cast([dbo].[fn_get_default_value] ('HighDate','Global')             as datetime)
,@def_global_default_load_date_time				= cast([dbo].[fn_get_default_value] ('DefaultLoadDateTime','Global')  as varchar(128))
,@def_global_failed_lookup_key					= cast([dbo].[fn_get_default_value] ('FailedLookupKey', 'Global')     as integer)
-- Hub Defaults
,@def_hub_schema                                = cast([dbo].[fn_get_default_value] ('schema','hub')                  as varchar(128))
-- Link Defaults
,@def_link_schema                               = cast([dbo].[fn_get_default_value] ('schema','lnk')                  as varchar(128))
-- Sat Defaults
,@def_sat_IsColumnStore							= cast([dbo].[fn_get_default_value] ('IsColumnStore','sat')			  as integer)

select @sat_start_date_col = quotename(column_name)
from [dbo].[dv_default_column]
where 1=1
and object_type = 'sat'
and object_column_type = 'Version_Start_Date'
select @sat_end_date_col = quotename(column_name)
from [dbo].[dv_default_column]
where 1=1
and object_type = 'sat'
and object_column_type = 'Version_End_Date'

SET @_Step = 'Get Source Table Details'
-- Object Specific Settings
-- Source Table
select   @source_system                         = s.[source_system_name]
        ,@source_database                       = s.[timevault_name]
        ,@source_schema                         = t.[source_table_schema]
        ,@source_table                          = t.[source_table_name]
        ,@source_table_config_key				= t.[source_table_key]
        ,@source_qualified_name					= quotename(s.[timevault_name]) + '.' + quotename(t.[source_table_schema]) + '.' + quotename(t.[source_table_name])
from [dbo].[dv_source_system] s
inner join [dbo].[dv_source_table] t
on t.system_key = s.[source_system_key]
where 1=1
and s.[source_system_name]						= @vault_source_system_name
and t.[source_table_schema]						= @vault_source_table_schema
and t.[source_table_name]						= @vault_source_table_name

SET @_Step = 'Get Satellite Details'
-- Satellite
select top 1 @sat_config_key					= sat.[satellite_key]
          ,@sat_link_hub_flag					= sat.[link_hub_satellite_flag]
		  ,@sat_duplicate_removal_threshold		= sat.[duplicate_removal_threshold]
from [dbo].[dv_source_table] t
inner join [dbo].[dv_column] c
on c.table_key = t.[source_table_key]
inner join [dbo].[dv_satellite_column] sc
on sc.column_key = c.column_key
inner join [dbo].[dv_satellite] sat
on sat.satellite_key = sc.satellite_key
where 1=1
and t.[source_table_key] = @source_table_config_key

select @sat_hashmatching_char_length = column_length from [dbo].[dv_default_column]
where 1=1
and [object_type] = 'Sat'
and [object_column_type] <> 'Object_Key' 
and [object_column_type] = 'Hash_Match'

SET @_Step = 'Get Hub Details'
-- Owner Hub Table
if @sat_link_hub_flag = 'H'
        select   @hub_database                  = h.[hub_database]
                ,@hub_schema                    = coalesce([hub_schema], @def_hub_schema, 'dbo')
                ,@hub_table                     = h.[hub_name]
           		,@hub_surrogate_keyname			= (select replace(replace(column_name, '[', ''), ']', '') from [dbo].[fn_get_key_definition](h.[hub_name], 'hub'))
                ,@hub_config_key                = h.[hub_key]
                ,@hub_qualified_name			= quotename([hub_database]) + '.' + quotename(coalesce([hub_schema], @def_hub_schema, 'dbo')) + '.' + quotename((select [dbo].[fn_get_object_name] ([hub_name], 'hub')))
        from [dbo].[dv_satellite] s
        inner join [dbo].[dv_hub] h
        on s.hub_key = h.hub_key
where 1=1
and s.[satellite_key] = @sat_config_key

SET @_Step = 'Get Link Details'
-- Owner Link Table
if @sat_link_hub_flag = 'L'
begin
        select   @link_database                 = l.[link_database]
                ,@link_schema                   = coalesce(l.[link_schema], @def_link_schema, 'dbo')
                ,@link_table                    = l.[link_name]
				,@link_surrogate_keyname		= (select replace(replace(column_name, '[', ''), ']', '') from [dbo].[fn_get_key_definition](l.[link_name], 'lnk'))
                ,@link_config_key               = l.[link_key]
                ,@link_qualified_name			= quotename([link_database]) + '.' + quotename(coalesce(l.[link_schema], @def_link_schema, 'dbo')) + '.' + quotename((select [dbo].[fn_get_object_name] ([link_name], 'lnk')))
        from [dbo].[dv_satellite] s
        inner join [dbo].[dv_link] l
        on s.link_key = l.link_key
    where 1=1
    and s.[satellite_key] = @sat_config_key


SET @_Step = 'Get Lookup Details'
set @link_lookup_joins = ''
set @link_hub_keys = ''

declare @c_hub_key                      int
    ,@c_hub_name                        varchar(128)
    ,@c_hub_schema						varchar(128)
    ,@c_hub_database					varchar(128)
    ,@c_hub_abbreviation				varchar(4)


set @link_hub_keys		= ''
set @wrk_link_keys		= ''
set @link_lookup_joins	= ''
set @wrk_hub_joins		= ''

DECLARE c_hub_key CURSOR FOR
select h.[hub_key]
      ,h.[hub_name]
      ,h.[hub_schema]
      ,h.[hub_database]
      ,h.[hub_abbreviation]

  FROM [dbo].[dv_link] l
  inner join [dbo].[dv_hub_link] hl
  on hl.[link_key] = l.[link_key]
  inner join [dbo].[dv_hub] h
  on h.[hub_key] = hl.[hub_key]
  where 1=1
  and l.[link_key] = @link_config_key
  order by hl.hub_link_key
OPEN c_hub_key
FETCH NEXT FROM c_hub_key
INTO @c_hub_key
    ,@c_hub_name
    ,@c_hub_schema
    ,@c_hub_database
    ,@c_hub_abbreviation


WHILE @@FETCH_STATUS = 0
BEGIN
    select @wrk_link_joins  = 'LEFT JOIN ' + quotename(@c_hub_database) + '.' + quotename(coalesce(@c_hub_schema, @def_hub_schema, 'dbo')) + '.' + quotename((select [dbo].[fn_get_object_name] (@c_hub_name, 'hub'))) + ' ' + @c_hub_abbreviation + @crlf + ' ON  '
    select @wrk_link_keys  += ' tmp.' + (select column_name from [dbo].[fn_get_key_definition](h.[hub_name], 'hub')) + 
						      ' = link.' + (select column_name from [dbo].[fn_get_key_definition](h.[hub_name], 'hub')) + @crlf + ' AND '
		  ,@wrk_link_joins += @c_hub_abbreviation + '.' + quotename(hkc.[hub_key_column_name]) + ' = CAST(src.' + quotename(c.[column_name]) + ' as ' + replace([dbo].[fn_build_column_definition] (c.[column_type],c.[column_length],c.[column_precision],c.[column_scale],c.[Collation_Name], 1,0), 'NULL','') + ')' + @crlf + ' AND '

        from [dbo].[dv_hub] h
        inner join [dbo].[dv_hub_key_column] hkc
        on h.hub_key = hkc.hub_key
        inner join [dbo].[dv_hub_column] hc
        on hc.hub_key_column_key = hkc.hub_key_column_key
        inner join [dbo].[dv_column] c
        on c.column_key = hc.column_key
        inner join [dbo].[dv_source_table] st
        on c.[table_key] = st.[source_table_key]
        where 1=1
        and h.hub_key = @c_hub_key
        and st.[source_table_key] = @source_table_config_key
        and c.discard_flag <> 1
        ORDER BY hkc.hub_key_ordinal_position

		select  @wrk_hub_joins += ', ' + @c_hub_abbreviation + '.' + (select column_name from [dbo].[fn_get_key_definition]([hub_name], 'hub'))  + @crlf
        from(
        select distinct hub_name--, hub_key_ordinal_position
        from [dbo].[dv_hub] h
        inner join [dbo].[dv_hub_key_column] hkc
        on h.hub_key = hkc.hub_key
        inner join [dbo].[dv_hub_column] hc
        on hc.hub_key_column_key = hkc.hub_key_column_key
        inner join [dbo].[dv_column] c
        on c.column_key = hc.column_key
        inner join [dbo].[dv_source_table] st
        on c.[table_key] = st.[source_table_key]
        where 1=1
        and h.hub_key = @c_hub_key
        and st.[source_table_key] = @source_table_config_key
        and c.discard_flag <> 1) hkc
        --ORDER BY hkc.hub_key_ordinal_position
        set @link_hub_keys = @link_hub_keys + @wrk_link_keys
		-------------------

        set @link_lookup_joins = @link_lookup_joins + left(@wrk_link_joins, len(@wrk_link_joins) - 4)
        FETCH NEXT FROM c_hub_key
        INTO @c_hub_key
                ,@c_hub_name
                ,@c_hub_schema
                ,@c_hub_database
                ,@c_hub_abbreviation
END

CLOSE c_hub_key
DEALLOCATE c_hub_key
select @wrk_link_keys = left(@wrk_link_keys, len(@wrk_link_keys) - 4)
end

SET @_Step = 'Get Load Date Spec.'
--- Use either a date time from the source or the default
select @source_load_date_time = [column_name]
from [dbo].[dv_source_table] st
inner join [dbo].[dv_column] c
on st.[source_table_key] = c.table_key
where 1=1
and st.[source_table_key] = @source_table_config_key
and c.[is_source_date] = 1
--NB do not check Discard Flag here as the Date Column may not be included in the Sat.
if @@rowcount > 1 RAISERROR ('Source Table has Multiple Source Dates Defined',16,1);
select @source_load_date_time = isnull(@source_load_date_time, @def_global_default_load_date_time)

SET @_Step = 'Get Payload Details'
-- Build the Source Payload NB 
set @sql = ''
select @sql += 'src.' +quotename([column_name]) + @crlf +', '
from [dbo].[dv_column]
where 1=1
and [discard_flag] <> 1
and [table_key] = @source_table_config_key
order by source_ordinal_position
select @source_payload = left(@sql, len(@sql) -1)

-- Temp Tables
SET @_Step = 'Get Temp Table Name Details'
select @temp_table_name_001 = '##temp_001_' + replace(cast(newid() as varchar(50)), '-', '')

-- Build the SQL to obtain Surrogate Keys, before Merging the Sat.
-- HUB based

-- Get the Key Match
SET @_Step = 'Get Match Key'

if @sat_link_hub_flag = 'H'
begin
        select @sql = ''
        --select @sql += 'hub.' + quotename(hkc.[hub_key_column_name]) + ' = CAST(src.' + quotename(c.[column_name]) + ' as ' + [hub_key_column_type] + ')' + @crlf + ' AND '
		select @sql += 'hub.' + quotename(hkc.[hub_key_column_name]) + ' = CAST(src.' + quotename(c.[column_name]) + ' as ' + replace([dbo].[fn_build_column_definition] (c.[column_type],c.[column_length],c.[column_precision],c.[column_scale],c.[Collation_Name], 1,0), 'NULL','') + ')' + @crlf + ' AND '
        from [dbo].[dv_hub] h
        inner join [dbo].[dv_hub_key_column] hkc
        on h.hub_key = hkc.hub_key
        inner join [dbo].[dv_hub_column] hc
        on hc.hub_key_column_key = hkc.hub_key_column_key
        inner join [dbo].[dv_column] c
        on c.column_key = hc.column_key
        inner join [dbo].[dv_source_table] st
        on c.[table_key] = st.[source_table_key]
        where 1=1
        and h.hub_key = @hub_config_key
        and st.[source_table_key] = @source_table_config_key
        and c.discard_flag <> 1
        ORDER BY hkc.hub_key_ordinal_position
        select @surrogate_key_match =  left(@sql, len(@sql) - 4)
end
-- Compile the SQL
-- If it is a link, create the temp table with all Hub keys plus a dummy for the Link Keys.
SET @_Step = 'Compile the SQL'
set @sql1 = ''
if @sat_link_hub_flag = 'H'
        set @sql1 = 'SELECT ' + quotename(@hub_surrogate_keyname) + ' = isnull(hub.' + quotename(@hub_surrogate_keyname) + ', ' + cast(@def_global_failed_lookup_key as varchar(50)) + ')' + @crlf

if @sat_link_hub_flag = 'L'
    begin
        set @sql1 = 'SELECT ' + quotename(@link_surrogate_keyname) + ' = cast(0 as integer) ' + @crlf
        set @sql1 = @sql1 + @wrk_hub_joins
        end

if not (@link_load_only = 'Y' and @sat_link_hub_flag = 'L')
        set @sql1 = @sql1 + ', ' + @source_payload
set @sql1 = @sql1 + ', [vault_load_time] = ' + @source_load_date_time + @crlf
set @sql1 = @sql1 + ', [vault_hashdiff]	 = cast('''' as varchar(' + cast(@sat_hashmatching_char_length as varchar) + '))' + @crlf
set @sql1 = @sql1 + ' INTO ' + @temp_table_name_001 + @crlf
set @sql1 = @sql1 + 'FROM ' + @source_qualified_name + ' src' + @crlf


if @sat_link_hub_flag = 'H'
        set @sql1 = @sql1 + 'LEFT JOIN ' + @hub_qualified_name + ' hub' + ' ON ' + @surrogate_key_match + @crlf

if @sat_link_hub_flag = 'L'
        set @sql1 = @sql1 + @link_lookup_joins
set @sql1 = @sql1 + ';' + @crlf

if (@sat_link_hub_flag = 'L' and @link_load_only <> 'Y')
        begin
        set @sql1 = @sql1 + @crlf + 'UPDATE tmp ' + @crlf
        set @sql1 = @sql1 + 'SET tmp.' + quotename(@link_surrogate_keyname) + ' = isnull(link.' + quotename(@link_surrogate_keyname) + ', ' + cast(@def_global_failed_lookup_key as varchar(50)) + ')' + @crlf
        set @sql1 = @sql1 + 'FROM ' + @temp_table_name_001 + ' tmp' + @crlf
        set @sql1 = @sql1 + 'LEFT JOIN ' + @link_qualified_name + ' link ' + @crlf + ' ON ' + @wrk_link_keys + ';'
        end

/****************************************************************************************************************************************/
-- Duplicate Checking
set @sql1 = @sql1 + @crlf

if (@sat_link_hub_flag = 'H' or (@sat_link_hub_flag = 'L' and @link_load_only <> 'Y'))
        begin
        if @sat_duplicate_removal_threshold > 0
        begin
        set @sql1 = @sql1 + 'select ''' + @temp_table_name_001 + ''' as global_temp_table_name, * into #t1 from ' + @temp_table_name_001 + ' where ' + case when @sat_link_hub_flag = 'H' then quotename(@hub_surrogate_keyname) else @link_surrogate_keyname end  + ' in( ' + @crlf
        set @sql1 = @sql1 + '        select top ' + cast(@sat_duplicate_removal_threshold + 1 as varchar) + case when @sat_link_hub_flag = 'H' then quotename(@hub_surrogate_keyname) else @link_surrogate_keyname end  + ' from '
                          + @temp_table_name_001 + ' group by ' + case when @sat_link_hub_flag = 'H' then quotename(@hub_surrogate_keyname) else @link_surrogate_keyname end  + ' having count(*) > 1)'  + @crlf
        set @sql1 = @sql1 + 'IF (select count(*) from #t1) > 0 ' + @crlf
        set @sql1 = @sql1 + '    begin' + @crlf
        set @sql1 = @sql1 + '    declare @xml1 varchar(max);' + @crlf
        set @sql1 = @sql1 + '    select  @xml1 = (select * from #t1 order by 2 for xml auto);' + @crlf
        set @sql1 = @sql1 + '    EXECUTE [log4].[JournalWriter]  @FunctionName = ''' + @_FunctionName + ''''
                                                            + ', @MessageText = ''Duplicate Keys Removed while Loading - ' + @source_qualified_name + ' - See [log4].[JournalDetail] for details'''
                                                            + ', @ExtraInfo = @xml1'
                                                            + ', @DatabaseName = ''' + @source_database + ''''
                                                            + ', @Task = ''Key Lookup before Loading Source Table'''
                                                            + ', @StepInFunction = ''Remove Duplicates before Loading Source Table'''
                                                            + ', @Severity = 256'
                                                            + ', @ExceptionId = 3601;' + @crlf

        set @sql1 = @sql1 + '    IF (select count(*) from #t1) >  ' + cast(@sat_duplicate_removal_threshold as varchar) + @crlf
        set @sql1 = @sql1 + '        raiserror (''Duplicate Keys Detected while Loading ' + @source_qualified_name + '''' + ', 16, 1)' + @crlf
        set @sql1 = @sql1 + '    else' + @crlf
        set @sql1 = @sql1 + '    DELETE FROM ' + @temp_table_name_001 + ' WHERE ' + case when @sat_link_hub_flag = 'H' then quotename(@hub_surrogate_keyname) else @link_surrogate_keyname end  + ' IN(' + @crlf
        set @sql1 = @sql1 + '           select distinct ' +  case when @sat_link_hub_flag = 'H' then quotename(@hub_surrogate_keyname) else @link_surrogate_keyname end  + ' FROM #t1); ' + @crlf
        set @sql1 = @sql1 + '    end' + @crlf

        end
        else
                set @sql1 = @sql1 + 'if exists (select 1 from ' + @temp_table_name_001 + ' group by ' + case when @sat_link_hub_flag = 'H' then quotename(@hub_surrogate_keyname) else @link_surrogate_keyname end  + ' having count(*) > 1)' + @crlf + '    raiserror (''Duplicate Keys Detected while Loading ' + @source_qualified_name + '''' + ', 16, 1)' + @crlf + @crlf
        end
/****************************************************************************************************************************************/

set @vault_sql_statement        = @sql1
select @vault_temp_table_name   = @temp_table_name_001
IF @_JournalOnOff = 'ON' SET @_ProgressText = @crlf + @vault_sql_statement + @crlf
/*--------------------------------------------------------------------------------------------------------------*/

select @vault_sql_statement

/*--------------------------------------------------------------------------------------------------------------*/

SET @_ProgressText  = @_ProgressText + @NEW_LINE
                                + 'Step: [' + @_Step + '] completed '

IF @@TRANCOUNT > 0 COMMIT TRAN;

SET @_Message   = 'Successfully Loaded Keys For: ' + @source_qualified_name

END TRY
BEGIN CATCH
SET @_ErrorContext      = 'Failed to Load Keys For: ' + @source_qualified_name
IF (XACT_STATE() = -1) -- uncommitable transaction
OR (@@TRANCOUNT > 0 AND XACT_STATE() != 1) -- undocumented uncommitable transaction
        BEGIN
                ROLLBACK TRAN;
                SET @_ErrorContext = @_ErrorContext + ' (Forced rolled back of all changes)';
        END

EXEC log4.ExceptionHandler
                  @ErrorContext  = @_ErrorContext
                , @ErrorNumber   = @_Error OUT
                , @ReturnMessage = @_Message OUT
                , @ExceptionId   = @_ExceptionId OUT
;
END CATCH

--/////////////////////////////////////////////////////////////////////////////////////////////////
OnComplete:
--/////////////////////////////////////////////////////////////////////////////////////////////////

        --! Clean up

        --!
        --! Use dbo.udf_FormatElapsedTime() to get a nicely formatted run time string e.g.
        --! "0 hr(s) 1 min(s) and 22 sec(s)" or "1345 milliseconds"
        --!
        IF @_Error = 0
                BEGIN
                        SET @_Step                      = 'OnComplete'
                        SET @_Severity          = @SEVERITY_SUCCESS
                        SET @_Message           = COALESCE(@_Message, @_Step)
                                                                + ' in a total run time of ' + log4.FormatElapsedTime(@_SprocStartTime, NULL, 3)
                        SET @_ProgressText  = @_ProgressText + @NEW_LINE + @_Message;
                END
        ELSE
                BEGIN
                        SET @_Step                      = COALESCE(@_Step, 'OnError')
                        SET @_Severity          = @SEVERITY_SEVERE
                        SET @_Message           = COALESCE(@_Message, @_Step)
                                                                + ' after a total run time of ' + log4.FormatElapsedTime(@_SprocStartTime, NULL, 3)
                        SET @_ProgressText  = @_ProgressText + @NEW_LINE + @_Message;
                END

        IF @_JournalOnOff = 'ON'
                EXEC log4.JournalWriter
                                  @Task                         = @_FunctionName
                                , @FunctionName         = @_FunctionName
                                , @StepInFunction       = @_Step
                                , @MessageText          = @_Message
                                , @Severity                     = @_Severity
                                , @ExceptionId          = @_ExceptionId
                                --! Supply all the progress info after we've gone to such trouble to collect it
                                , @ExtraInfo        = @_ProgressText

        --! Finally, throw an exception that will be detected by the caller
        IF @DoThrowError = 1 AND @_Error > 0
                RAISERROR(@_Message, 16, 99);

        SET NOCOUNT OFF;

        --! Return the value of @@ERROR (which will be zero on success)
        RETURN (@_Error);
END