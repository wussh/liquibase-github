--liquibase formatted sql

--changeset developer:001-create-users-table labels:v1.0 context:all
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(100) NOT NULL,
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_users          PRIMARY KEY (id),
    CONSTRAINT uq_users_username UNIQUE (username)
);
--rollback DROP TABLE IF EXISTS users;

--changeset developer:002-create-users-email-placeholder labels:v1.0 context:all
-- placeholder: email akan ditambah di v1.1
SELECT 1;
--rollback SELECT 1;
