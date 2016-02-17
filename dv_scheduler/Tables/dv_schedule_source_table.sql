﻿CREATE TABLE [dv_scheduler].[dv_schedule_source_table] (
    [schedule_source_table_key] INT                IDENTITY (1, 1) NOT NULL,
    [schedule_key]              INT                NOT NULL,
    [source_table_key]          INT                NOT NULL,
    [source_table_load_type]    VARCHAR (50)       CONSTRAINT [DF_dv_schedule_source_table_source_table_load_type] DEFAULT ('Full') NOT NULL,
    [priority]                  VARCHAR (50)       NOT NULL,
    [queue]                     VARCHAR (50)       NOT NULL,
    [is_cancelled]              BIT                CONSTRAINT [DF_dv_schedule_source_table_is_deleted] DEFAULT ((0)) NOT NULL,
    [release_key]               INT                CONSTRAINT [DF__dv_schedule_source_table_release_key] DEFAULT ((0)) NOT NULL,
    [version_number]            INT                CONSTRAINT [DF__dv_schedule_source_table__version___534D60F1] DEFAULT ((1)) NOT NULL,
    [updated_by]                VARCHAR (30)       CONSTRAINT [DF__dv_schedule_source_table__updated___5441852A] DEFAULT (user_name()) NOT NULL,
    [updated_datetime]          DATETIMEOFFSET (7) CONSTRAINT [DF__dv_schedule_source_table__updated___5535A963] DEFAULT (sysdatetimeoffset()) NOT NULL,
    CONSTRAINT [PK__dv_sched__5FF3626055109B18] PRIMARY KEY CLUSTERED ([schedule_source_table_key] ASC),
    CONSTRAINT [CK_dv_schedule_source_table__run_type] CHECK ([source_table_load_type]='Full' OR [source_table_load_type]='Delta' OR [source_table_load_type]='Default'),
    CONSTRAINT [FK_dv_schedule_source_table_dv_release_master] FOREIGN KEY ([release_key]) REFERENCES [dv_release].[dv_release_master] ([release_key]),
    CONSTRAINT [FK_dv_schedule_source_table_dv_schedule] FOREIGN KEY ([schedule_key]) REFERENCES [dv_scheduler].[dv_schedule] ([schedule_key]),
    CONSTRAINT [FK_dv_schedule_source_table_dv_source_table] FOREIGN KEY ([source_table_key]) REFERENCES [dbo].[dv_source_table] ([source_table_key])
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [dv_schedule__dv_schedule__dv_source_table]
    ON [dv_scheduler].[dv_schedule_source_table]([schedule_key] ASC, [source_table_key] ASC);