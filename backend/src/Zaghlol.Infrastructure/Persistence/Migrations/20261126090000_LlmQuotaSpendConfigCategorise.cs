using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-323 (ask-llm §4.5, llm-categorise §4): the six tables of the LLM helper, expand-only. Plain SQL outside the EF model (like
    /// the T-135 table), so the model snapshot is unchanged. No table has a column that can hold a question text; the only subject
    /// identifier is <c>llm_quota_counters.subject_id</c>, and the two categorise review tables carry only the peppered
    /// <c>install_hash</c>. Down drops the tables (and with them their grants).
    /// </summary>
    public partial class LlmQuotaSpendConfigCategorise : Migration
    {
        // The same backstop as merchant_contributions (FU-018): no run of 6 digits (ASCII, Arabic-Indic, Extended Arabic-Indic,
        // fullwidth) separated by up to three whitespace/dot/comma/slash/underscore/Arabic-comma/dash characters, no '@'.
        internal const string Sql =
                """
                CREATE TABLE zaghlol.llm_quota_counters (
                  feature text NOT NULL,
                  subject_kind text NOT NULL,
                  subject_id uuid NOT NULL,
                  month_key integer NOT NULL,
                  used integer NOT NULL,
                  last_request_hash bytea,
                  updated_at timestamptz NOT NULL,
                  CONSTRAINT pk_llm_quota_counters PRIMARY KEY (feature, subject_kind, subject_id, month_key),
                  CONSTRAINT ck_llm_quota_counters_feature CHECK (feature IN ('ask','cat')),
                  CONSTRAINT ck_llm_quota_counters_subject_kind CHECK (subject_kind IN ('install','account')),
                  CONSTRAINT ck_llm_quota_counters_month_key CHECK (month_key BETWEEN 202601 AND 209912),
                  CONSTRAINT ck_llm_quota_counters_used CHECK (used >= 0)
                );
                CREATE TABLE zaghlol.llm_spend_daily (
                  day date NOT NULL,
                  feature text NOT NULL,
                  provider_id text NOT NULL,
                  model text NOT NULL,
                  calls integer NOT NULL,
                  input_tokens bigint NOT NULL,
                  cached_tokens bigint NOT NULL,
                  output_tokens bigint NOT NULL,
                  cost_usd numeric(14,6) NOT NULL,
                  CONSTRAINT pk_llm_spend_daily PRIMARY KEY (day, feature, provider_id, model),
                  CONSTRAINT ck_llm_spend_daily_feature CHECK (feature IN ('ask','cat'))
                );
                CREATE TABLE zaghlol.remote_config (
                  key text NOT NULL,
                  value text NOT NULL,
                  version bigint NOT NULL,
                  updated_by uuid,
                  updated_at timestamptz NOT NULL,
                  CONSTRAINT pk_remote_config PRIMARY KEY (key)
                );
                CREATE TABLE zaghlol.llm_cat_answer_cache (
                  merchant_norm text NOT NULL,
                  category_code text NOT NULL,
                  confidence smallint NOT NULL,
                  provider_id text NOT NULL,
                  prompt_version text NOT NULL,
                  created_at timestamptz NOT NULL,
                  expires_at timestamptz NOT NULL,
                  hits integer NOT NULL DEFAULT 0,
                  CONSTRAINT pk_llm_cat_answer_cache PRIMARY KEY (merchant_norm),
                  CONSTRAINT ck_llm_cat_answer_cache_confidence CHECK (confidence BETWEEN 0 AND 100),
                  CONSTRAINT ck_llm_cat_answer_cache_merchant_norm CHECK (char_length(merchant_norm) BETWEEN 2 AND 64
                    AND merchant_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].,/_،-]{0,3}){6,}' AND position('@' in merchant_norm) = 0)
                );
                CREATE TABLE zaghlol.llm_cat_confirmations (
                  id uuid NOT NULL,
                  merchant_norm text NOT NULL,
                  category_code text NOT NULL,
                  source text NOT NULL,
                  install_hash bytea NOT NULL,
                  created_at timestamptz NOT NULL,
                  status text NOT NULL DEFAULT 'collecting',
                  CONSTRAINT pk_llm_cat_confirmations PRIMARY KEY (id),
                  CONSTRAINT uq_llm_cat_confirmations_merchant_install UNIQUE (merchant_norm, install_hash),
                  CONSTRAINT ck_llm_cat_confirmations_source CHECK (source IN ('llm','cache','catalog')),
                  CONSTRAINT ck_llm_cat_confirmations_status CHECK (status IN ('collecting','promoted','rejected')),
                  CONSTRAINT ck_llm_cat_confirmations_merchant_norm CHECK (char_length(merchant_norm) BETWEEN 2 AND 64
                    AND merchant_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].,/_،-]{0,3}){6,}' AND position('@' in merchant_norm) = 0)
                );
                CREATE TABLE zaghlol.llm_cat_corrections (
                  id uuid NOT NULL,
                  merchant_norm text NOT NULL,
                  ai_category text NOT NULL,
                  user_category text NOT NULL,
                  source text NOT NULL,
                  install_hash bytea NOT NULL,
                  created_at timestamptz NOT NULL,
                  status text NOT NULL DEFAULT 'open',
                  operator_id uuid,
                  resolved_at timestamptz,
                  CONSTRAINT pk_llm_cat_corrections PRIMARY KEY (id),
                  CONSTRAINT uq_llm_cat_corrections_merchant_install UNIQUE (merchant_norm, install_hash),
                  CONSTRAINT ck_llm_cat_corrections_source CHECK (source IN ('llm','cache','catalog')),
                  CONSTRAINT ck_llm_cat_corrections_status CHECK (status IN ('open','promoted','rejected','prompt_issue')),
                  CONSTRAINT ck_llm_cat_corrections_merchant_norm CHECK (char_length(merchant_norm) BETWEEN 2 AND 64
                    AND merchant_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].,/_،-]{0,3}){6,}' AND position('@' in merchant_norm) = 0)
                );
                """;

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(Sql);
            migrationBuilder.Sql(GrantMatrix.ToSql(GrantMatrix.LlmTables));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder) =>
            migrationBuilder.Sql(
                """
                DROP TABLE zaghlol.llm_cat_corrections;
                DROP TABLE zaghlol.llm_cat_confirmations;
                DROP TABLE zaghlol.llm_cat_answer_cache;
                DROP TABLE zaghlol.remote_config;
                DROP TABLE zaghlol.llm_spend_daily;
                DROP TABLE zaghlol.llm_quota_counters;
                """);
    }
}
