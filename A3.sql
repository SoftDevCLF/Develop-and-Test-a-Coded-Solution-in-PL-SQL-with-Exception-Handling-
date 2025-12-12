--WKIS Company program for accounting system
-- •	This is a double-entry accounting system that uses the accounting rules presented in the Accounting Notes document in Brightspace.

DECLARE
--Constants for transaction types
k_debit CONSTANT CHAR(1) := 'D';
k_credit CONSTANT CHAR(1) := 'C';

invalid_transaction_type EXCEPTION;  --custom exception for invalid transcation type

--Variables for error logging
v_error_logged BOOLEAN;
v_error_msg VARCHAR2(400);

--Variables to hold counts and totals
v_debit_total NUMBER;
v_credit_total NUMBER;

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
    JOIN account a ON nt.account_no = a.account_no
    JOIN account_type at ON a.account_type_code = at.account_type_code
    WHERE nt.transaction_no = p_no;
    
BEGIN
  --Loop through each distinct transaction
  FOR r_transaction IN c_transaction LOOP
    --Reset error flag and totals for each transaction
    v_error_logged := FALSE;
    v_debit_total := 0;
    v_credit_total := 0;

  -- *****Handle NULL transaction_no rows (missing transaction number)*****
    IF r_transaction.transaction_no IS NULL THEN
      v_error_msg := 'Missing transaction number. Cannot process transaction.';
      INSERT INTO wkis_error_log(transaction_no, transaction_date, description, error_msg)
      VALUES (NULL, r_transaction.transaction_date, r_transaction.description, v_error_msg);
      COMMIT;
      v_error_logged := TRUE;
    END IF;

  --******Embedded block to process each non-NULL transaction number*****
    BEGIN
      IF NOT v_error_logged THEN
      --Loop through transaction_detail to process each row for the current transaction
        FOR r_transaction_details IN c_transaction_details(r_transaction.transaction_no) LOOP

          --******Validate transaction type using constants and not hard-coded values in the loop*****
          IF (r_transaction_details.transaction_type NOT IN (k_debit, k_credit)) AND NOT v_error_logged THEN
            v_error_msg := 'Invalid transaction type "' || NVL(r_transaction_details.transaction_type,'NULL') || '" for account ' || NVL(TO_CHAR(r_transaction_details.account_no),'NULL') || '. Only characters D for Debit or C for Credit are allowed.';
            INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
            VALUES (r_transaction.transaction_no, r_transaction.transaction_date, r_transaction.description, v_error_msg);
            v_error_logged := TRUE;
          END IF;

          -- ******Validate negative or NULL transaction amount for each row in the loop*****
          IF (r_transaction_details.transaction_amount IS NULL OR r_transaction_details.transaction_amount < 0) AND NOT v_error_logged THEN
            v_error_msg := 'Negative or NULL amount (' || NVL(TO_CHAR(r_transaction_details.transaction_amount),'NULL') || ') for account ' || NVL(TO_CHAR(r_transaction_details.account_no),'NULL') || '.';
            INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
            VALUES (r_transaction.transaction_no, r_transaction.transaction_date, r_transaction.description, v_error_msg);
            v_error_logged := TRUE;
          END IF;

          --******Validation of invalid account number (basically if the account does not exist)*****
          --(logic here)

          --******If the transaction had no errors, accumulate total debit and total credit***** 
          IF NOT v_error_logged THEN
            IF r_transaction_details.transaction_type = k_debit THEN
              v_debit_total := NVL(v_debit_total,0) + r_transaction_details.transaction_amount;
            ELSE
              v_credit_total := NVL(v_credit_total,0) + r_transaction_details.transaction_amount;
            END IF;
          END IF;
        END LOOP;
      END IF;

      --******Debits must equal credits for a valid transaction: error when Debits ≠ credits******
      IF NOT v_error_logged AND NVL(v_debit_total,0) <> NVL(v_credit_total,0) THEN
        v_error_msg := 'The debits and credits are not equal in this transaction.';
        INSERT INTO wkis_error_log(transaction_no, transaction_date, description, error_msg)
        VALUES(r_transaction.transaction_no, r_transaction.transaction_date, r_transaction.description, v_error_msg);
        v_error_logged := TRUE;
        CONTINUE;
      END IF;

      --******After all validation, proceed with inserts and updates******  
      IF NOT v_error_logged THEN

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
        DELETE FROM new_transactions
              WHERE transaction_no = r_transaction.transaction_no;

        --Commit the successful transaction processing
        COMMIT;
      END IF;
    
    EXCEPTION
    --Invalid Transaction Type
    WHEN invalid_transaction_type THEN
        IF NOT v_error_logged THEN
          v_error_msg := 'Invalid transaction type detected. Only D or C allowed.';

          INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
          VALUES (r_transaction.transaction_no,
                  r_transaction.transaction_date,
                  r_transaction.description,
                  v_error_msg);

          v_error_logged := TRUE;
        END IF;

        ROLLBACK;

    --When others (System errors)
    WHEN OTHERS THEN
        IF NOT v_error_logged THEN
          v_error_msg := 'System error: ' || SQLERRM;

          INSERT INTO wkis_error_log (transaction_no, transaction_date, description, error_msg)
          VALUES (r_transaction.transaction_no,
                  r_transaction.transaction_date,
                  r_transaction.description,
                  v_error_msg);

          v_error_logged := TRUE;
        END IF;

        ROLLBACK;
    
    END;
  END LOOP;
END;
/
