--liquibase formatted sql

--changeset developer:003-add-email-column labels:v1.1 context:all
ALTER TABLE users
    ADD COLUMN email VARCHAR(255) NULL AFTER username,
    ADD CONSTRAINT uq_users_email UNIQUE (email);
--rollback ALTER TABLE users DROP INDEX uq_users_email;
--rollback ALTER TABLE users DROP COLUMN email;
