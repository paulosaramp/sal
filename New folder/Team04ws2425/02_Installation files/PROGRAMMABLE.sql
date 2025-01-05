-- stored procedure for updating credit hour account
CREATE OR REPLACE PROCEDURE INSTANCE.SP_UPDATE_CREDIT_HOUR_ACCOUNT(
    IN semester_start VARCHAR(10)
)
LANGUAGE SQL
BEGIN
    DECLARE total_credited_teacher_hours INT DEFAULT 0;
    DECLARE function_load INT DEFAULT 0;
    DECLARE v_teacher_id VARCHAR(15);
    DECLARE done INT DEFAULT 0;

    -- go through all active professors
    DECLARE cur CURSOR FOR
        SELECT teacher_id
        FROM INSTANCE.PROFESSOR
        WHERE is_active = TRUE;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
    OPEN cur;
    FETCH cur INTO v_teacher_id;

    -- loop through 
    WHILE done = 0 DO
        SET total_credited_teacher_hours = 0;
        SET function_load = 0;

        -- calculate credited teacher hours
        SELECT COALESCE(SUM(credited_teacher_hours), 0)
        INTO total_credited_teacher_hours
        FROM INSTANCE.COURSE
        WHERE teacher = v_teacher_id
          AND course_start = semester_start;

        -- calculate function load from FUNCTION_PROFESSOR
        SELECT COALESCE(SUM(load), 0)
        INTO function_load
        FROM INSTANCE.FUNCTION_PROFESSOR
        WHERE PROFESSOR = v_teacher_id
          AND FUNCTION_START = semester_start;

        -- add function load to the credited teacher hours
        SET total_credited_teacher_hours = total_credited_teacher_hours + function_load;

        -- subtract compulsory hours (18) from the total
        SET total_credited_teacher_hours = total_credited_teacher_hours - 18;

        -- update credit hour account
        UPDATE INSTANCE.PROFESSOR
        SET credit_hour_account = credit_hour_account + total_credited_teacher_hours
        WHERE teacher_id = v_teacher_id;

        FETCH cur INTO v_teacher_id;
    END WHILE;
    CLOSE cur;
END
@

-- function for missing courses
CREATE OR REPLACE FUNCTION INSTANCE.F_MISSING_COURSES_CHECK(
    v_MAJOR VARCHAR(5),
    v_SEMESTER INTEGER
)
RETURNS INTEGER
LANGUAGE SQL
BEGIN
    DECLARE course_count INTEGER;

    -- Select the count of matching courses
    SELECT COUNT(*) 
    INTO course_count
    FROM INSTANCE.COURSE
    INNER JOIN INSTANCE.SUBJECT SU
        ON INSTANCE.COURSE.SUBJECT = SU.SUBJECT_NUMBER
    INNER JOIN INSTANCE.SEARCH_CRITERIA SC
        ON INSTANCE.COURSE.COURSE_START = SC.SEMESTER_START
    WHERE SU.MAJOR = v_MAJOR AND SU.SEMESTER = v_SEMESTER;

     -- Conditional logic for returning a message
    IF course_count > 0 THEN
        RETURN 0;  -- Or another success code
    ELSE
        RETURN -1;  -- Or another failure code
    END IF;
END
@

-- Trigger to update PROFESSOR
CREATE OR REPLACE TRIGGER INSTANCE.TR_UPDATE_CREDIT_HOUR_ACCOUNT
AFTER UPDATE OF semester_start ON INSTANCE.SEARCH_CRITERIA
REFERENCING OLD AS OLD_ROW NEW AS NEW_ROW
FOR EACH ROW
BEGIN
    -- Only if there is a difference
    IF OLD_ROW.semester_start <> NEW_ROW.semester_start THEN
        -- Call stored procedure with the new semester_start value
        CALL INSTANCE.SP_UPDATE_CREDIT_HOUR_ACCOUNT(NEW_ROW.semester_start);
    END IF;
END
@

-- trigger for PROFESSOR table
CREATE OR REPLACE TRIGGER INSTANCE.TR_CHECK_EXISTING_LECTURER
BEFORE INSERT ON instance.professor
REFERENCING NEW AS NEW_ROW
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM instance.lecturer WHERE teacher_id = NEW_ROW.teacher_id) THEN
        SIGNAL SQLSTATE '45000';
    END IF;
END
@

-- trigger for LECTURER table
CREATE OR REPLACE TRIGGER INSTANCE.TR_CHECK_EXISTING_PROFESSOR
BEFORE INSERT ON instance.lecturer
REFERENCING NEW AS NEW_ROW
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM instance.professor WHERE teacher_id = NEW_ROW.teacher_id) THEN
        SIGNAL SQLSTATE '45000';
    END IF;
END
@
CREATE OR REPLACE TRIGGER ${nameWithSchemaName}
BEFORE INSERT ON INSTANCE.COURSE
REFERENCING NEW AS NEW_ROW
FOR EACH ROW
BEGIN
    DECLARE is_active BOOLEAN DEFAULT FALSE;
    -- is prof active?
    SELECT IS_ACTIVE INTO is_active
    FROM INSTANCE.PROFESSOR
    WHERE TEACHER_ID = NEW_ROW.TEACHER;
    -- if prof inactive / not found, check the lecturer table
    IF is_active = FALSE THEN
        SELECT IS_ACTIVE INTO is_active
        FROM INSTANCE.LECTURER
        WHERE TEACHER_ID = NEW_ROW.TEACHER;
    END IF;
    --if inactive for both
    IF is_active = FALSE THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot insert course for inactive professor or lecturer';
    END IF;
END
@
