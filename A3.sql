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
    JOIN account a ON nt.account_no = a.account_no
    JOIN account_type at ON a.account_type_code = at.account_type_code
    WHERE nt.transaction_no = p_no;

    --Variables
    total_debits NUMBER := 0;
    total_credits NUMBER := 0;
    error_found BOOLEAN := FALSE;
    
BEGIN
  --Outer Loop through each distinct transaction in new_transactions
  FOR r_transaction IN c_transaction LOOP
    total_debits := 0;
    total_credits := 0;
    error_found := FALSE;

    -- Missing (Null) Transactions
    IF r_transaction.transaction_no IS NULL THEN
      INSERT INTO WKIS_ERROR_LOG (transaction_no, transaction_date, description, error_msg)
      VALUES(NULL, r_transaction.transaction_date, r_transaction.description, 'Missing a transaction number. Sorry, the transaction cannot be processed.');
      error_found := TRUE;
    END IF;

    --Skip entire transaction if error occurs
    IF error_found THEN
      CONTINUE;
    END IF;
  
    --Inner Loop through and insert into transaction_detail
    FOR r_transaction_details IN c_transaction_details(r_transaction.transaction_no) LOOP
    --Transaction Type with Debit & Credits
      IF r_transaction_details.transaction_type = 'D' THEN
        total_debits := r_transaction_details.transaction_amount + total_debits;
      ELSIF r_transaction_details.transaction_type = 'C' THEN
        total_credits := r_transaction_details.transaction_amount + total_credits;
      END IF;

      --Insert into transaction_detail
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

    --Check total Debits ≠ Credits 
    IF total_debits != total_credits THEN
      INSERT INTO WKIS_ERROR_LOG (transaction_no, transaction_date, description, error_msg)
      VALUES(r_transaction.transaction_no, r_transaction.transaction_date, r_transaction.description, 'The debits and credits are not equal in this transaction.');
      error_found := TRUE;
    END IF; 

       --Skips the inserts if there is an error
    IF error_found THEN
      CONTINUE;
    END IF;
      

    --Insert into transaction_history
    INSERT INTO transaction_history (transaction_no, transaction_date, description)
    VALUES (r_transaction.transaction_no, r_transaction.transaction_date, r_transaction.description);


    --Remove processed rows from holding table
    DELETE FROM new_transactions
    WHERE transaction_no = r_transaction.transaction_no;
  END LOOP;
  
  --Commit the changes
  COMMIT;
END;
/
