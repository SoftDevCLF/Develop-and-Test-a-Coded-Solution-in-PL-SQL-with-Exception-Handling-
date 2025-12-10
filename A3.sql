--WKIS Company program for accounting system
-- •	This is a double-entry accounting system that uses the accounting rules presented in the Accounting Notes document in Brightspace.
-- •	Take transactions from a holding table named NEW_TRANSACTIONS and insert them into the TRANSACTION_DETAIL and TRANSACTION_HISTORY tables.
-- •	At the same time, update the appropriate account balance in the ACCOUNT table. 
-- •	You need to determine the default transaction type of an account (debit (D) or credit (C)) to decide whether to add or subtract when updating the account balance. 
-- •	Once a transaction is successfully processed, it should be removed from the holding table.

DECLARE
    --Outer cursor to fetch records from new_transactions
    CURSOR c_transaction IS
        SELECT DISTINCT transaction_no, transaction_date, description
        FROM new_transactions
        ORDER BY transaction_no;

    --Inner cursor for all rows belonging to one transaction
    CURSOR c_transaction_details(p_no NUMBER) IS
        SELECT nt.account_no,
            nt.transaction_type,
            nt.transaction_amount,
            at.default_trans_type
        FROM new_transactions nt
        LEFT JOIN account a ON nt.account_no = a.account_no
        LEFT JOIN account_type at ON a.account_type_code = at.account_type_code
        WHERE nt.transaction_no = p_no;

    ex_invalid_account EXCEPTION;
    ex_negative_amount EXCEPTION;

    v_has_error BOOLEAN := FALSE;
    
BEGIN
    --Loop through each distinct transaction in new_transactions
    FOR r_transaction IN c_transaction LOOP

        -- Validates each transation against Exception Handlers        
        BEGIN 

            FOR r_transaction_details IN c_transaction_details(r_transaction.transaction_no) LOOP

                -- Validate that the transaction amount is not negative 
                -- If negative, raise custom exception to log the error and skip processing
                IF r_transaction_details.transaction_amount < 0 THEN
                    RAISE ex_negative_amount;
                END IF;

                -- Validate that the account exists by checking its default transaction type
                -- If NULL, the account number is invalid, so raise custom exception
                IF r_transaction_details.default_trans_type IS NULL THEN
                    RAISE ex_invalid_account;
                END IF;

            END LOOP;

        --Insert into transaction_history
        INSERT INTO transaction_history (transaction_no, transaction_date, description)
        VALUES (r_transaction.transaction_no, r_transaction.transaction_date, r_transaction.description);

    --Loop through and insert into transaction_detail
    FOR r_transaction_details IN c_transaction_details(r_transaction.transaction_no) LOOP
        INSERT INTO transaction_detail
            (account_no, transaction_no, transaction_type, transaction_amount)
        VALUES
            (r_transaction_details.account_no, r_transaction.transaction_no, r_transaction_details.transaction_type, r_transaction_details.transaction_amount);

        --Update account balance based on transaction type
        IF r_transaction_details.transaction_type = r_transaction_details.default_trans_type THEN
            UPDATE account
            SET account_balance = account_balance + r_transaction_details.transaction_amount
            WHERE account_no = r_transaction_details.account_no;
        ELSE
            UPDATE account
            SET account_balance = account_balance - r_transaction_details.transaction_amount
            WHERE account_no = r_transaction_details.account_no;
        END IF;
    END LOOP;

    --Remove processed rows from holding table
    IF NOT v_has_error THEN
        DELETE FROM new_transactions
        WHERE transaction_no = r_transaction.transaction_no;
    END IF;

    -- Exception handling
    EXCEPTION 

        -- Invalid account number Exception
        WHEN ex_invalid_account THEN
            INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
            VALUES (r_transaction.transaction_no,
                    r_transaction.transaction_date,
                    r_transaction.description,
                    'Invalid account number in transaction.');
            v_has_error := TRUE;

        -- Negative transaction amount Exception 
        WHEN ex_negative_amount THEN 
            INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
            VALUES (r_transaction.transaction_no,
                    r_transaction.transaction_date,
                    r_transaction.description,
                    'Negative transaction amount not allowed.');
            v_has_error := TRUE;

    END;

  END LOOP;
  
  --Commit the changes
  COMMIT;
END;
/

SELECT *
FROM wkis_error_log
ORDER BY transaction_no;
