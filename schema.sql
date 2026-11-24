CREATE DATABASE IF NOT EXISTS elderly_care_billing
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE elderly_care_billing;

-- 所有业务日期区间统一为 [start_date, end_date)，end_date 为 NULL 表示持续生效。
-- MySQL 没有区间排除约束，床位、老人、价格和套餐区间的互斥需在 service 事务中加锁校验。

CREATE TABLE institutions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(32) NOT NULL,
  name VARCHAR(100) NOT NULL,
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_institutions_code (code)
) ENGINE = InnoDB COMMENT = '机构表：维护养老院或分支机构档案；机构编码全局唯一，停用后保留全部业务历史。';

CREATE TABLE users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NULL,
  username VARCHAR(64) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  name VARCHAR(50) NOT NULL,
  phone VARCHAR(20) NULL,
  role ENUM('SYSTEM_ADMIN', 'ORG_FINANCE') NOT NULL,
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  last_login_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_username (username),
  UNIQUE KEY uk_users_institution_id_id (institution_id, id),
  CONSTRAINT fk_users_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_users_role_institution CHECK (
    (role = 'SYSTEM_ADMIN' AND institution_id IS NULL)
    OR (role = 'ORG_FINANCE' AND institution_id IS NOT NULL)
  )
) ENGINE = InnoDB COMMENT = '用户表：SYSTEM_ADMIN 为不绑定机构的系统管理员，ORG_FINANCE 为单账号单机构的财务人员；密码仅保存哈希。';

CREATE TABLE buildings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  code VARCHAR(32) NOT NULL,
  name VARCHAR(100) NOT NULL,
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_buildings_institution_code (institution_id, code),
  UNIQUE KEY uk_buildings_institution_id_id (institution_id, id),
  KEY idx_buildings_institution_status (institution_id, status),
  CONSTRAINT fk_buildings_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB COMMENT = '楼栋表：维护机构下楼栋档案；楼栋编码在同一机构内唯一，已使用楼栋只允许停用。';

CREATE TABLE rooms (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  building_id BIGINT UNSIGNED NOT NULL,
  room_no VARCHAR(32) NOT NULL,
  floor VARCHAR(20) NULL,
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_rooms_institution_room_no (institution_id, room_no),
  UNIQUE KEY uk_rooms_institution_id_id (institution_id, id),
  KEY idx_rooms_institution_building (institution_id, building_id),
  CONSTRAINT fk_rooms_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_rooms_building
    FOREIGN KEY (institution_id, building_id) REFERENCES buildings (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB COMMENT = '房间表：维护楼栋下的房间信息；房间号在同一机构内唯一，房间与楼栋必须属于同一机构。';

CREATE TABLE bed_types (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  code VARCHAR(32) NOT NULL,
  name VARCHAR(100) NOT NULL,
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_bed_types_institution_code (institution_id, code),
  UNIQUE KEY uk_bed_types_institution_id_id (institution_id, id),
  CONSTRAINT fk_bed_types_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB COMMENT = '床型表：维护单人间、双人间等床型档案；床型编码在同一机构内唯一，具体床位费由床型价格配置决定。';

CREATE TABLE beds (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  room_id BIGINT UNSIGNED NOT NULL,
  bed_type_id BIGINT UNSIGNED NOT NULL,
  bed_no VARCHAR(32) NOT NULL,
  status ENUM('AVAILABLE', 'OCCUPIED', 'DISABLED') NOT NULL DEFAULT 'AVAILABLE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_beds_institution_bed_no (institution_id, bed_no),
  UNIQUE KEY uk_beds_institution_id_id (institution_id, id),
  KEY idx_beds_institution_room_status (institution_id, room_id, status),
  KEY idx_beds_institution_type_status (institution_id, bed_type_id, status),
  CONSTRAINT fk_beds_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_beds_room
    FOREIGN KEY (institution_id, room_id) REFERENCES rooms (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_beds_bed_type
    FOREIGN KEY (institution_id, bed_type_id) REFERENCES bed_types (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB COMMENT = '床位表：维护实际床位及空闲、占用、停用状态；床位号在同一机构内唯一，房间与床型均须属于同一机构。';

CREATE TABLE charge_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  item_code VARCHAR(32) NOT NULL,
  name VARCHAR(100) NOT NULL,
  category ENUM('BED', 'CARE', 'FOOD', 'OTHER') NOT NULL,
  billing_mode ENUM('MONTHLY', 'PER_USE', 'ONE_TIME') NOT NULL,
  unit VARCHAR(16) NOT NULL,
  default_price_fen BIGINT UNSIGNED NOT NULL,
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_charge_items_institution_code (institution_id, item_code),
  UNIQUE KEY uk_charge_items_institution_id_id (institution_id, id),
  KEY idx_charge_items_institution_mode_status (institution_id, billing_mode, status),
  CONSTRAINT fk_charge_items_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB COMMENT = '收费项目表：维护床位、护理、餐饮等收费目录；billing_mode 区分按月、按次和一次计费，default_price_fen 为默认单价分值。';

CREATE TABLE bed_type_prices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  bed_type_id BIGINT UNSIGNED NOT NULL,
  charge_item_id BIGINT UNSIGNED NOT NULL,
  unit_price_fen BIGINT UNSIGNED NOT NULL,
  effective_from DATE NOT NULL,
  effective_to DATE NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_by BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_bed_type_prices_institution_id_id (institution_id, id),
  UNIQUE KEY uk_bed_type_prices_start (institution_id, bed_type_id, charge_item_id, effective_from),
  KEY idx_bed_type_prices_lookup (institution_id, bed_type_id, charge_item_id, effective_from, effective_to),
  CONSTRAINT fk_bed_type_prices_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bed_type_prices_bed_type
    FOREIGN KEY (institution_id, bed_type_id) REFERENCES bed_types (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bed_type_prices_charge_item
    FOREIGN KEY (institution_id, charge_item_id) REFERENCES charge_items (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bed_type_prices_creator
    FOREIGN KEY (institution_id, created_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_bed_type_prices_interval CHECK (
    effective_to IS NULL OR effective_to > effective_from
  )
) ENGINE = InnoDB COMMENT = '床型价格表：按床型、收费项目和生效区间维护床位单价；同一床型同一项目的价格区间不得重叠，历史账单不受改价影响。';

CREATE TABLE packages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  package_code VARCHAR(32) NOT NULL,
  name VARCHAR(100) NOT NULL,
  description VARCHAR(500) NULL,
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_packages_institution_code (institution_id, package_code),
  UNIQUE KEY uk_packages_institution_id_id (institution_id, id),
  CONSTRAINT fk_packages_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB COMMENT = '基础套餐模板表：维护护理、餐饮等非床位项目的套餐模板；套餐总价由 package_items 汇总，不包含床位费。';

CREATE TABLE package_items (
  institution_id BIGINT UNSIGNED NOT NULL,
  package_id BIGINT UNSIGNED NOT NULL,
  charge_item_id BIGINT UNSIGNED NOT NULL,
  quantity DECIMAL(10, 3) NOT NULL DEFAULT 1,
  unit_price_fen BIGINT UNSIGNED NOT NULL,
  sort_no INT NOT NULL DEFAULT 0,
  PRIMARY KEY (package_id, charge_item_id),
  KEY idx_package_items_institution_item (institution_id, charge_item_id),
  CONSTRAINT fk_package_items_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_package_items_package
    FOREIGN KEY (institution_id, package_id) REFERENCES packages (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_package_items_charge_item
    FOREIGN KEY (institution_id, charge_item_id) REFERENCES charge_items (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_package_items_quantity CHECK (quantity > 0)
) ENGINE = InnoDB COMMENT = '套餐模板明细表：保存套餐包含的非床位月费项目、数量和模板单价；同一套餐内收费项目唯一，模板改价不影响已设置套餐的老人。';

CREATE TABLE residents (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  resident_no VARCHAR(32) NOT NULL,
  name VARCHAR(50) NOT NULL,
  gender ENUM('UNKNOWN', 'MALE', 'FEMALE') NOT NULL DEFAULT 'UNKNOWN',
  birth_date DATE NULL,
  care_level VARCHAR(50) NULL,
  contact_name VARCHAR(50) NULL,
  contact_phone VARCHAR(20) NULL,
  status ENUM('PENDING', 'IN_RESIDENCE', 'CHECKED_OUT') NOT NULL DEFAULT 'PENDING',
  check_in_date DATE NULL,
  check_out_date DATE NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_residents_institution_no (institution_id, resident_no),
  UNIQUE KEY uk_residents_institution_id_id (institution_id, id),
  KEY idx_residents_institution_status_name (institution_id, status, name),
  CONSTRAINT fk_residents_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_residents_stay_interval CHECK (
    check_in_date IS NULL
    OR check_out_date IS NULL
    OR check_out_date >= check_in_date
  ),
  CONSTRAINT ck_residents_in_residence CHECK (
    status <> 'IN_RESIDENCE'
    OR (check_in_date IS NOT NULL AND check_out_date IS NULL)
  ),
  CONSTRAINT ck_residents_checked_out CHECK (
    status <> 'CHECKED_OUT'
    OR (check_in_date IS NOT NULL AND check_out_date IS NOT NULL)
  )
) ENGINE = InnoDB COMMENT = '老人档案表：维护老人基本资料、联系人和入住退住状态；入住日计费、退住日不计费，实际居住区间为左闭右开。';

CREATE TABLE bed_assignments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  resident_id BIGINT UNSIGNED NOT NULL,
  bed_id BIGINT UNSIGNED NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NULL,
  status ENUM('ACTIVE', 'ENDED') NOT NULL DEFAULT 'ACTIVE',
  active_resident_id BIGINT UNSIGNED GENERATED ALWAYS AS (
    CASE WHEN status = 'ACTIVE' THEN resident_id ELSE NULL END
  ) STORED,
  active_bed_id BIGINT UNSIGNED GENERATED ALWAYS AS (
    CASE WHEN status = 'ACTIVE' THEN bed_id ELSE NULL END
  ) STORED,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_by BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_bed_assignments_institution_id_id (institution_id, id),
  UNIQUE KEY uk_bed_assignments_exact_start (institution_id, resident_id, bed_id, start_date),
  UNIQUE KEY uk_bed_assignments_active_resident (institution_id, active_resident_id),
  UNIQUE KEY uk_bed_assignments_active_bed (institution_id, active_bed_id),
  KEY idx_bed_assignments_resident (institution_id, resident_id, start_date, end_date),
  KEY idx_bed_assignments_bed (institution_id, bed_id, start_date, end_date),
  CONSTRAINT fk_bed_assignments_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bed_assignments_resident
    FOREIGN KEY (institution_id, resident_id) REFERENCES residents (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bed_assignments_bed
    FOREIGN KEY (institution_id, bed_id) REFERENCES beds (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bed_assignments_creator
    FOREIGN KEY (institution_id, created_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_bed_assignments_interval CHECK (
    end_date IS NULL OR end_date >= start_date
  ),
  CONSTRAINT ck_bed_assignments_status CHECK (
    (status = 'ACTIVE' AND end_date IS NULL)
    OR (status = 'ENDED' AND end_date IS NOT NULL)
  )
) ENGINE = InnoDB COMMENT = '床位分配表：按左闭右开区间记录老人床位分配；调床时结束原区间并连续开启新区间，同一老人或床位最多一条生效分配。';

CREATE TABLE resident_packages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  resident_id BIGINT UNSIGNED NOT NULL,
  package_id BIGINT UNSIGNED NOT NULL,
  package_code_snapshot VARCHAR(32) NOT NULL,
  package_name_snapshot VARCHAR(100) NOT NULL,
  effective_from DATE NOT NULL,
  effective_to DATE NULL,
  status ENUM('ACTIVE', 'ENDED') NOT NULL DEFAULT 'ACTIVE',
  active_resident_id BIGINT UNSIGNED GENERATED ALWAYS AS (
    CASE WHEN status = 'ACTIVE' THEN resident_id ELSE NULL END
  ) STORED,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_by BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_resident_packages_institution_id_id (institution_id, id),
  UNIQUE KEY uk_resident_packages_start (institution_id, resident_id, effective_from),
  UNIQUE KEY uk_resident_packages_active_resident (institution_id, active_resident_id),
  KEY idx_resident_packages_resident (institution_id, resident_id, effective_from, effective_to),
  CONSTRAINT fk_resident_packages_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_resident_packages_resident
    FOREIGN KEY (institution_id, resident_id) REFERENCES residents (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_resident_packages_package
    FOREIGN KEY (institution_id, package_id) REFERENCES packages (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_resident_packages_creator
    FOREIGN KEY (institution_id, created_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_resident_packages_interval CHECK (
    effective_to IS NULL OR effective_to >= effective_from
  ),
  CONSTRAINT ck_resident_packages_status CHECK (
    (status = 'ACTIVE' AND effective_to IS NULL)
    OR (status = 'ENDED' AND effective_to IS NOT NULL)
  )
) ENGINE = InnoDB COMMENT = '老人套餐表：记录老人基础套餐的生效区间及模板名称快照；同一老人最多一条生效套餐，历史区间不得重叠。';

CREATE TABLE resident_package_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  resident_package_id BIGINT UNSIGNED NOT NULL,
  charge_item_id BIGINT UNSIGNED NOT NULL,
  item_name_snapshot VARCHAR(100) NOT NULL,
  billing_mode_snapshot ENUM('MONTHLY') NOT NULL,
  unit_snapshot VARCHAR(16) NOT NULL,
  quantity DECIMAL(10, 3) NOT NULL,
  unit_price_fen BIGINT UNSIGNED NOT NULL,
  sort_no INT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_resident_package_items_package_item (resident_package_id, charge_item_id),
  UNIQUE KEY uk_resident_package_items_institution_id_id (institution_id, id),
  KEY idx_resident_package_items_item (institution_id, charge_item_id),
  CONSTRAINT fk_resident_package_items_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_resident_package_items_assignment
    FOREIGN KEY (institution_id, resident_package_id) REFERENCES resident_packages (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_resident_package_items_charge_item
    FOREIGN KEY (institution_id, charge_item_id) REFERENCES charge_items (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_resident_package_items_quantity CHECK (quantity > 0)
) ENGINE = InnoDB COMMENT = '老人套餐明细快照表：设置老人套餐时复制非床位月费项目的名称、单位、数量和单价；套餐模板后续改价不改变本表。';

CREATE TABLE service_charges (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  resident_id BIGINT UNSIGNED NOT NULL,
  charge_item_id BIGINT UNSIGNED NOT NULL,
  item_name_snapshot VARCHAR(100) NOT NULL,
  service_date DATE NOT NULL,
  quantity DECIMAL(10, 3) NOT NULL,
  unit_price_fen BIGINT UNSIGNED NOT NULL,
  amount_fen BIGINT UNSIGNED NOT NULL,
  source_type VARCHAR(32) NOT NULL DEFAULT 'MANUAL',
  source_no VARCHAR(64) NULL,
  status ENUM('ACTIVE', 'VOID') NOT NULL DEFAULT 'ACTIVE',
  void_reason VARCHAR(255) NULL,
  voided_at DATETIME(3) NULL,
  voided_by BIGINT UNSIGNED NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_by BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_service_charges_institution_id_id (institution_id, id),
  UNIQUE KEY uk_service_charges_source (institution_id, source_type, source_no),
  KEY idx_service_charges_resident_date (institution_id, resident_id, service_date, status),
  KEY idx_service_charges_date_status (institution_id, service_date, status),
  CONSTRAINT fk_service_charges_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_service_charges_resident
    FOREIGN KEY (institution_id, resident_id) REFERENCES residents (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_service_charges_charge_item
    FOREIGN KEY (institution_id, charge_item_id) REFERENCES charge_items (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_service_charges_creator
    FOREIGN KEY (institution_id, created_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_service_charges_voider
    FOREIGN KEY (institution_id, voided_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_service_charges_quantity CHECK (quantity > 0),
  CONSTRAINT ck_service_charges_void CHECK (
    (status = 'ACTIVE' AND void_reason IS NULL AND voided_at IS NULL AND voided_by IS NULL)
    OR (status = 'VOID' AND void_reason IS NOT NULL AND voided_at IS NOT NULL AND voided_by IS NOT NULL)
  )
) ENGINE = InnoDB COMMENT = '服务用量表：记录老人实际发生的按次或一次性服务及价格金额快照；来源单据同机构内唯一，作废保留原因和操作人。';

CREATE TABLE bills (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  resident_id BIGINT UNSIGNED NOT NULL,
  bill_no VARCHAR(64) NOT NULL,
  bill_type ENUM('REGULAR', 'ADJUSTMENT') NOT NULL DEFAULT 'REGULAR',
  original_bill_id BIGINT UNSIGNED NULL,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  total_amount_fen BIGINT NOT NULL,
  status ENUM('DRAFT', 'ISSUED', 'VOID') NOT NULL DEFAULT 'DRAFT',
  idempotency_key VARCHAR(128) NULL,
  issued_at DATETIME(3) NULL,
  issued_by BIGINT UNSIGNED NULL,
  voided_at DATETIME(3) NULL,
  voided_by BIGINT UNSIGNED NULL,
  void_reason VARCHAR(255) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_by BIGINT UNSIGNED NOT NULL,
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  -- 作废账单不占用账期，允许使用新幂等键重开。
  regular_period_start DATE GENERATED ALWAYS AS (
    CASE WHEN bill_type = 'REGULAR' AND status <> 'VOID' THEN period_start ELSE NULL END
  ) STORED,
  regular_period_end DATE GENERATED ALWAYS AS (
    CASE WHEN bill_type = 'REGULAR' AND status <> 'VOID' THEN period_end ELSE NULL END
  ) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uk_bills_institution_no (institution_id, bill_no),
  UNIQUE KEY uk_bills_institution_id_id (institution_id, id),
  UNIQUE KEY uk_bills_regular_period (institution_id, resident_id, regular_period_start, regular_period_end),
  KEY idx_bills_resident_period (institution_id, resident_id, period_start, period_end, status),
  KEY idx_bills_status_period (institution_id, status, period_start, period_end),
  KEY idx_bills_original (institution_id, original_bill_id),
  CONSTRAINT fk_bills_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bills_resident
    FOREIGN KEY (institution_id, resident_id) REFERENCES residents (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bills_original
    FOREIGN KEY (institution_id, original_bill_id) REFERENCES bills (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bills_creator
    FOREIGN KEY (institution_id, created_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bills_issuer
    FOREIGN KEY (institution_id, issued_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bills_voider
    FOREIGN KEY (institution_id, voided_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_bills_period CHECK (period_end > period_start),
  CONSTRAINT ck_bills_regular_total CHECK (
    bill_type <> 'REGULAR' OR total_amount_fen >= 0
  ),
  CONSTRAINT ck_bills_original CHECK (
    (bill_type = 'REGULAR' AND original_bill_id IS NULL AND idempotency_key IS NOT NULL)
    OR (bill_type = 'ADJUSTMENT' AND original_bill_id IS NOT NULL AND original_bill_id <> id)
  ),
  CONSTRAINT ck_bills_status CHECK (
    (status = 'DRAFT' AND issued_at IS NULL AND issued_by IS NULL AND voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL)
    OR (status = 'ISSUED' AND issued_at IS NOT NULL AND issued_by IS NOT NULL AND voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL)
    OR (status = 'VOID' AND issued_at IS NOT NULL AND issued_by IS NOT NULL AND voided_at IS NOT NULL AND voided_by IS NOT NULL AND void_reason IS NOT NULL)
  )
) ENGINE = InnoDB COMMENT = '账单主表：维护自然月常规账单和调整账单；已出账内容不可直接修改，作废后释放账期，可使用新幂等键重开。';

CREATE TABLE bill_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  bill_id BIGINT UNSIGNED NOT NULL,
  line_no INT NOT NULL,
  source_type ENUM('BED', 'PACKAGE', 'SERVICE', 'ADJUSTMENT') NOT NULL,
  source_id BIGINT UNSIGNED NULL,
  source_key VARCHAR(191) NOT NULL,
  charge_item_id BIGINT UNSIGNED NULL,
  item_name_snapshot VARCHAR(100) NOT NULL,
  billing_mode_snapshot ENUM('MONTHLY', 'PER_USE', 'ONE_TIME', 'ADJUSTMENT') NOT NULL,
  unit_snapshot VARCHAR(16) NOT NULL,
  quantity DECIMAL(10, 3) NOT NULL,
  unit_price_fen BIGINT NOT NULL,
  stay_days INT NULL,
  month_days INT NULL,
  segment_start DATE NULL,
  segment_end DATE NULL,
  amount_fen BIGINT NOT NULL,
  calculation_json JSON NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_bill_items_bill_line (bill_id, line_no),
  UNIQUE KEY uk_bill_items_bill_source (bill_id, source_key),
  KEY idx_bill_items_institution_charge_item (institution_id, charge_item_id),
  CONSTRAINT fk_bill_items_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bill_items_bill
    FOREIGN KEY (institution_id, bill_id) REFERENCES bills (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bill_items_charge_item
    FOREIGN KEY (institution_id, charge_item_id) REFERENCES charge_items (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_bill_items_line CHECK (line_no > 0),
  CONSTRAINT ck_bill_items_non_adjustment CHECK (
    source_type = 'ADJUSTMENT'
    OR (quantity >= 0 AND unit_price_fen >= 0 AND amount_fen >= 0)
  ),
  CONSTRAINT ck_bill_items_days CHECK (
    (stay_days IS NULL OR stay_days >= 0)
    AND (month_days IS NULL OR month_days BETWEEN 28 AND 31)
    AND (stay_days IS NULL OR month_days IS NULL OR stay_days <= month_days)
  ),
  CONSTRAINT ck_bill_items_segment CHECK (
    (segment_start IS NULL AND segment_end IS NULL)
    OR (segment_start IS NOT NULL AND segment_end IS NOT NULL AND segment_end > segment_start)
  )
) ENGINE = InnoDB COMMENT = '账单明细表：保存床位、套餐、服务或调整行的价格与计算依据快照；月费按分段居住天数独立四舍五入到分，调整行金额可为负。';

CREATE TABLE bill_adjustments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  original_bill_id BIGINT UNSIGNED NOT NULL,
  adjustment_bill_id BIGINT UNSIGNED NOT NULL,
  reason VARCHAR(255) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_by BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_bill_adjustments_adjustment_bill (adjustment_bill_id),
  UNIQUE KEY uk_bill_adjustments_institution_id_id (institution_id, id),
  CONSTRAINT fk_bill_adjustments_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bill_adjustments_original
    FOREIGN KEY (institution_id, original_bill_id) REFERENCES bills (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bill_adjustments_adjustment
    FOREIGN KEY (institution_id, adjustment_bill_id) REFERENCES bills (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bill_adjustments_creator
    FOREIGN KEY (institution_id, created_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_bill_adjustments_distinct CHECK (original_bill_id <> adjustment_bill_id)
) ENGINE = InnoDB COMMENT = '账单调整关系表：关联原账单与调整账单并记录调整原因；调整明细保存在调整账单的 bill_items 中，不覆盖原账单。';

CREATE TABLE payments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  bill_id BIGINT UNSIGNED NOT NULL,
  payment_no VARCHAR(64) NOT NULL,
  amount_fen BIGINT UNSIGNED NOT NULL,
  method ENUM('CASH', 'BANK_TRANSFER', 'WECHAT', 'ALIPAY', 'OTHER') NOT NULL,
  paid_at DATETIME(3) NOT NULL,
  external_trade_no VARCHAR(128) NULL,
  status ENUM('ACTIVE', 'REVERSED') NOT NULL DEFAULT 'ACTIVE',
  note VARCHAR(255) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_by BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_payments_institution_no (institution_id, payment_no),
  UNIQUE KEY uk_payments_institution_id_id (institution_id, id),
  UNIQUE KEY uk_payments_external_trade_no (institution_id, method, external_trade_no),
  KEY idx_payments_bill_status (institution_id, bill_id, status),
  KEY idx_payments_paid_at (institution_id, paid_at),
  CONSTRAINT fk_payments_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_payments_bill
    FOREIGN KEY (institution_id, bill_id) REFERENCES bills (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_payments_creator
    FOREIGN KEY (institution_id, created_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_payments_amount CHECK (amount_fen > 0)
) ENGINE = InnoDB COMMENT = '收款记录表：登记已出账账单的现金、转账等收款；支付流水号同机构同方式内唯一，状态分为有效和已冲正，禁止超额收款由服务层校验。';

CREATE TABLE payment_reversals (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  payment_id BIGINT UNSIGNED NOT NULL,
  reversal_no VARCHAR(64) NOT NULL,
  reason VARCHAR(255) NOT NULL,
  reversed_at DATETIME(3) NOT NULL,
  reversed_by BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_payment_reversals_institution_no (institution_id, reversal_no),
  UNIQUE KEY uk_payment_reversals_payment (payment_id),
  UNIQUE KEY uk_payment_reversals_institution_id_id (institution_id, id),
  CONSTRAINT fk_payment_reversals_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_payment_reversals_payment
    FOREIGN KEY (institution_id, payment_id) REFERENCES payments (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_payment_reversals_reverser
    FOREIGN KEY (institution_id, reversed_by) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB COMMENT = '收款冲正表：记录收款冲正原因、时间及操作人；每笔收款最多冲正一次，原收款记录保留并标记为已冲正。';

CREATE TABLE idempotency_keys (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  operation VARCHAR(64) NOT NULL,
  idempotency_key VARCHAR(128) NOT NULL,
  request_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  status ENUM('IN_PROGRESS', 'COMPLETED') NOT NULL DEFAULT 'IN_PROGRESS',
  resource_type VARCHAR(64) NULL,
  resource_id BIGINT UNSIGNED NULL,
  response_status SMALLINT NULL,
  response_body JSON NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  completed_at DATETIME(3) NULL,
  expires_at DATETIME(3) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_idempotency_scope (institution_id, user_id, operation, idempotency_key),
  KEY idx_idempotency_expires (expires_at),
  CONSTRAINT fk_idempotency_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_idempotency_user
    FOREIGN KEY (institution_id, user_id) REFERENCES users (institution_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT ck_idempotency_completed CHECK (
    (status = 'IN_PROGRESS' AND completed_at IS NULL)
    OR (status = 'COMPLETED' AND completed_at IS NOT NULL AND response_status IS NOT NULL)
  )
) ENGINE = InnoDB COMMENT = '幂等键表：按机构、用户、操作和幂等键去重写请求；request_hash 用于拒绝同一幂等键搭配不同请求内容，并保存执行结果。';

CREATE TABLE audit_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id BIGINT UNSIGNED NULL,
  user_id BIGINT UNSIGNED NULL,
  action VARCHAR(64) NOT NULL,
  entity_type VARCHAR(64) NOT NULL,
  entity_id BIGINT UNSIGNED NULL,
  before_json JSON NULL,
  after_json JSON NULL,
  reason VARCHAR(255) NULL,
  request_id VARCHAR(64) NULL,
  ip_address VARCHAR(45) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_audit_entity (institution_id, entity_type, entity_id, created_at),
  KEY idx_audit_created_at (created_at),
  CONSTRAINT fk_audit_institution
    FOREIGN KEY (institution_id) REFERENCES institutions (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_audit_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB COMMENT = '审计日志表：记录关键业务操作、实体、修改前后内容、原因、请求及操作人；机构字段可为空以容纳系统管理员操作。';
