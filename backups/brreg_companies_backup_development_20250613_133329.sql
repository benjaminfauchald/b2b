--
-- PostgreSQL database dump
--

-- Dumped from database version 12.22 (Ubuntu 12.22-0ubuntu0.20.04.4)
-- Dumped by pg_dump version 12.22 (Ubuntu 12.22-0ubuntu0.20.04.4)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: brreg; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.brreg (
    id bigint NOT NULL,
    organisasjonsnummer character varying NOT NULL,
    navn text NOT NULL,
    organisasjonsform_kode text,
    organisasjonsform_beskrivelse text,
    naeringskode1_kode text,
    naeringskode1_beskrivelse text,
    naeringskode2_kode text,
    naeringskode2_beskrivelse text,
    naeringskode3_kode text,
    naeringskode3_beskrivelse text,
    aktivitet text,
    antallansatte integer,
    hjemmeside text,
    epost text,
    telefon text,
    mobiltelefon text,
    forretningsadresse text,
    forretningsadresse_poststed text,
    forretningsadresse_postnummer text,
    forretningsadresse_kommune text,
    forretningsadresse_land text,
    driftsinntekter bigint,
    driftskostnad bigint,
    "ordinaertResultat" bigint,
    aarsresultat bigint,
    mvaregistrert boolean,
    mvaregistrertdato date,
    frivilligmvaregistrert boolean,
    frivilligmvaregistrertdato date,
    stiftelsesdato date,
    konkurs boolean,
    konkursdato date,
    underavvikling boolean,
    avviklingsdato date,
    linked_in text,
    linked_in_ai text,
    linked_in_alternatives jsonb,
    linked_in_processed boolean DEFAULT false,
    linked_in_last_processed_at timestamp(6) without time zone,
    http_error integer,
    http_error_message text,
    brreg_result_raw jsonb,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.brreg OWNER TO postgres;

--
-- Name: brreg_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.brreg_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.brreg_id_seq OWNER TO postgres;

--
-- Name: brreg_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.brreg_id_seq OWNED BY public.brreg.id;


--
-- Name: companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.companies (
    id bigint NOT NULL,
    source_country character varying(2) NOT NULL,
    source_registry character varying(20) NOT NULL,
    source_id text NOT NULL,
    registration_number text NOT NULL,
    company_name text NOT NULL,
    organization_form_code text,
    organization_form_description text,
    registration_date date,
    deregistration_date date,
    deregistration_reason text,
    registration_country text,
    primary_industry_code text,
    primary_industry_description text,
    secondary_industry_code text,
    secondary_industry_description text,
    tertiary_industry_code text,
    tertiary_industry_description text,
    business_description text,
    segment text,
    industry text,
    has_registered_employees boolean,
    employee_count integer,
    employee_registration_date_registry date,
    employee_registration_date_nav date,
    linkedin_employee_count integer,
    website text,
    email text,
    phone text,
    mobile text,
    postal_address text,
    postal_city text,
    postal_code text,
    postal_municipality text,
    postal_municipality_code text,
    postal_country text,
    postal_country_code text,
    business_address text,
    business_city text,
    business_postal_code text,
    business_municipality text,
    business_municipality_code text,
    business_country text,
    business_country_code text,
    last_submitted_annual_report integer,
    ordinary_result bigint,
    annual_result bigint,
    operating_revenue bigint,
    operating_costs bigint,
    linkedin_url text,
    linkedin_ai_url text,
    linkedin_alt_url text,
    linkedin_alternatives jsonb,
    linkedin_processed boolean DEFAULT false,
    linkedin_last_processed_at timestamp(6) without time zone,
    linkedin_ai_confidence integer,
    sps_match text,
    sps_match_percentage text,
    http_error integer,
    http_error_message text,
    source_raw_data jsonb,
    brreg_id integer,
    country character varying(2),
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.companies OWNER TO postgres;

--
-- Name: companies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.companies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.companies_id_seq OWNER TO postgres;

--
-- Name: companies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.companies_id_seq OWNED BY public.companies.id;


--
-- Name: brreg id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.brreg ALTER COLUMN id SET DEFAULT nextval('public.brreg_id_seq'::regclass);


--
-- Name: companies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies ALTER COLUMN id SET DEFAULT nextval('public.companies_id_seq'::regclass);


--
-- Data for Name: brreg; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.brreg (id, organisasjonsnummer, navn, organisasjonsform_kode, organisasjonsform_beskrivelse, naeringskode1_kode, naeringskode1_beskrivelse, naeringskode2_kode, naeringskode2_beskrivelse, naeringskode3_kode, naeringskode3_beskrivelse, aktivitet, antallansatte, hjemmeside, epost, telefon, mobiltelefon, forretningsadresse, forretningsadresse_poststed, forretningsadresse_postnummer, forretningsadresse_kommune, forretningsadresse_land, driftsinntekter, driftskostnad, "ordinaertResultat", aarsresultat, mvaregistrert, mvaregistrertdato, frivilligmvaregistrert, frivilligmvaregistrertdato, stiftelsesdato, konkurs, konkursdato, underavvikling, avviklingsdato, linked_in, linked_in_ai, linked_in_alternatives, linked_in_processed, linked_in_last_processed_at, http_error, http_error_message, brreg_result_raw, description, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: companies; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.companies (id, source_country, source_registry, source_id, registration_number, company_name, organization_form_code, organization_form_description, registration_date, deregistration_date, deregistration_reason, registration_country, primary_industry_code, primary_industry_description, secondary_industry_code, secondary_industry_description, tertiary_industry_code, tertiary_industry_description, business_description, segment, industry, has_registered_employees, employee_count, employee_registration_date_registry, employee_registration_date_nav, linkedin_employee_count, website, email, phone, mobile, postal_address, postal_city, postal_code, postal_municipality, postal_municipality_code, postal_country, postal_country_code, business_address, business_city, business_postal_code, business_municipality, business_municipality_code, business_country, business_country_code, last_submitted_annual_report, ordinary_result, annual_result, operating_revenue, operating_costs, linkedin_url, linkedin_ai_url, linkedin_alt_url, linkedin_alternatives, linkedin_processed, linkedin_last_processed_at, linkedin_ai_confidence, sps_match, sps_match_percentage, http_error, http_error_message, source_raw_data, brreg_id, country, description, created_at, updated_at) FROM stdin;
\.


--
-- Name: brreg_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.brreg_id_seq', 1, false);


--
-- Name: companies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.companies_id_seq', 1, false);


--
-- Name: brreg brreg_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.brreg
    ADD CONSTRAINT brreg_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: index_brreg_on_driftsinntekter; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_brreg_on_driftsinntekter ON public.brreg USING btree (driftsinntekter);


--
-- Name: index_brreg_on_linked_in_ai; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_brreg_on_linked_in_ai ON public.brreg USING btree (linked_in_ai);


--
-- Name: index_brreg_on_organisasjonsform_beskrivelse; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_brreg_on_organisasjonsform_beskrivelse ON public.brreg USING btree (organisasjonsform_beskrivelse);


--
-- Name: index_brreg_on_organisasjonsnummer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX index_brreg_on_organisasjonsnummer ON public.brreg USING btree (organisasjonsnummer);


--
-- Name: index_companies_on_linkedin_ai_url; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_companies_on_linkedin_ai_url ON public.companies USING btree (linkedin_ai_url);


--
-- Name: index_companies_on_operating_revenue; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_companies_on_operating_revenue ON public.companies USING btree (operating_revenue);


--
-- Name: index_companies_on_organization_form_description; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_companies_on_organization_form_description ON public.companies USING btree (organization_form_description);


--
-- Name: index_companies_on_source_country_and_source_registry; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX index_companies_on_source_country_and_source_registry ON public.companies USING btree (source_country, source_registry);


--
-- PostgreSQL database dump complete
--

