CREATE ROLE admin;
CREATE ROLE client;

GRANT ALL ON ALL TABLES IN SCHEMA public TO admin;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO client;

-- SELECT pid, usename, query FROM pg_stat_activity; выводит процессы
-- SELECT pg_terminate_backend(12345); удаление процесса по PID
