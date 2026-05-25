--liquibase formatted sql

--changeset developer:002-create-orders-table labels:v1.0 context:all
CREATE TABLE orders (
    id         BIGINT         NOT NULL AUTO_INCREMENT,
    user_id    BIGINT         NOT NULL,
    total      DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
    status     VARCHAR(50)    NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_orders         PRIMARY KEY (id),
    CONSTRAINT fk_orders_user_id FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
--rollback DROP TABLE IF EXISTS orders;
