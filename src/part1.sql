DROP TABLE IF EXISTS personal_data CASCADE;
CREATE TABLE personal_data (
  customer_id INTEGER PRIMARY KEY,
  customer_name VARCHAR NOT NULL CHECK (customer_name ~ '^[A-ZА-Я][a-zа-я -]+'),
  customer_surname VARCHAR NOT NULL CHECK (customer_surname ~ '^[A-ZА-Я][a-zа-я -]+'),
  customer_primary_email VARCHAR NOT NULL CHECK (customer_primary_email ~ '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$'),
  customer_primary_phone VARCHAR NOT NULL CHECK (customer_primary_phone ~ '^[+][7][0-9]{10}'));
  
DROP TABLE IF EXISTS cards CASCADE;
CREATE TABLE cards (
  customer_card_id INTEGER PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES personal_data(customer_id) ON UPDATE CASCADE ON DELETE CASCADE);

DROP TABLE IF EXISTS transactions CASCADE;
CREATE TABLE transactions (
  transaction_id INTEGER PRIMARY KEY,
  customer_card_id INTEGER NOT NULL REFERENCES cards(customer_card_id) ON UPDATE CASCADE ON DELETE CASCADE,
  transaction_summ NUMERIC NOT NULL CHECK (transaction_summ::VARCHAR ~ '[0-9.]+'),
  transaction_datetime TIMESTAMP NOT NULL CHECK (transaction_datetime::VARCHAR ~ '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{1,2}:[0-9]{2}:[0-9]{2}'),
  transaction_store_id INTEGER NOT NULL);

DROP TABLE IF EXISTS groups_sku CASCADE;
CREATE TABLE groups_sku (
  group_id INTEGER PRIMARY KEY,
  group_name VARCHAR NOT NULL CHECK (group_name ~ '[A-Za-zА-Яа-я0-9!$()*+.,;@#~:<=>?[\\\]^{|}-]+'));

DROP TABLE IF EXISTS sku CASCADE;
CREATE TABLE sku (
  sku_id INTEGER PRIMARY KEY,
  sku_name VARCHAR NOT NULL CHECK (sku_name ~ '[A-Za-zА-Яа-я0-9!$()*+.,;@#~:<=>?[\\\]^{|}-]+'),
  group_id INTEGER NOT NULL REFERENCES groups_sku(group_id) ON UPDATE CASCADE ON DELETE CASCADE);

DROP TABLE IF EXISTS checks CASCADE;
CREATE TABLE checks (
  transaction_id INTEGER NOT NULL REFERENCES transactions(transaction_id) ON UPDATE CASCADE ON DELETE CASCADE,
  sku_id INTEGER NOT NULL REFERENCES sku(sku_id) ON UPDATE CASCADE ON DELETE CASCADE,
  sku_amount NUMERIC NOT NULL CHECK (sku_amount::VARCHAR ~ '[0-9.]+'),
  sku_summ NUMERIC NOT NULL CHECK (sku_summ::VARCHAR ~ '[0-9.]+'),
  sku_summ_paid NUMERIC NOT NULL CHECK (sku_summ_paid::VARCHAR ~ '[0-9.]+'),
  sku_discount NUMERIC NOT NULL CHECK (sku_discount::VARCHAR ~ '[0-9.]+'));

DROP TABLE IF EXISTS stores CASCADE;
CREATE TABLE stores (
  transaction_store_id INTEGER,
  sku_id INTEGER NOT NULL REFERENCES sku(sku_id) ON UPDATE CASCADE ON DELETE CASCADE,
  sku_purchase_price NUMERIC NOT NULL CHECK (sku_purchase_price::VARCHAR ~ '[0-9.]+'),
  sku_retail_price NUMERIC NOT NULL CHECK (sku_retail_price::VARCHAR ~ '[0-9.]+'));

DROP TABLE IF EXISTS date_of_analysis_formation CASCADE;
CREATE TABLE date_of_analysis_formation (
  analysis_formation TIMESTAMP NOT NULL CHECK (analysis_formation::VARCHAR ~ '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{1,2}:[0-9]{2}:[0-9]{2}'));


CREATE OR REPLACE PROCEDURE csv_import(tab VARCHAR, filepath VARCHAR, delim VARCHAR)
AS
$$
BEGIN
    EXECUTE FORMAT('COPY %s FROM %s WITH (delimiter %s, format csv);', tab, filepath, delim);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE csv_export(tab VARCHAR, filepath VARCHAR, delim VARCHAR)
AS
$$
BEGIN
    EXECUTE FORMAT('COPY %s TO %s DELIMITER %s CSV;', tab, filepath, delim);
END;
$$ LANGUAGE plpgsql;


-- Before import copy datasets folder in /tmp
CALL csv_import('personal_data', '''/tmp/datasets/Personal_Data_Mini.tsv''', E'''\t''');
CALL csv_import('cards', '''/tmp/datasets/Cards_Mini.tsv''', E'''\t''');
CALL csv_import('transactions', '''/tmp/datasets/Transactions_Mini.tsv''', E'''\t''');
CALL csv_import('groups_sku', '''/tmp/datasets/Groups_SKU_Mini.tsv''', E'''\t''');
CALL csv_import('sku', '''/tmp/datasets/SKU_Mini.tsv''', E'''\t''');
CALL csv_import('checks', '''/tmp/datasets/Checks_Mini.tsv''', E'''\t''');
CALL csv_import('stores', '''/tmp/datasets/Stores_Mini.tsv''', E'''\t''');
CALL csv_import('date_of_analysis_formation', '''/tmp/datasets/Date_Of_Analysis_Formation.tsv''', E'''\t''');
