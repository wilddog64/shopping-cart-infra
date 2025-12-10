-- Products Database Schema
-- Shopping Cart Application - Product Catalog Service

-- Create products table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    category VARCHAR(100),
    inventory_count INTEGER NOT NULL DEFAULT 0 CHECK (inventory_count >= 0),
    image_url VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index on SKU for fast lookups
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);

-- Create index on category for filtering
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);

-- Create index on created_at for sorting
CREATE INDEX IF NOT EXISTS idx_products_created_at ON products(created_at DESC);

-- Create categories table for better organization
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    parent_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index on category parent_id for hierarchical queries
CREATE INDEX IF NOT EXISTS idx_categories_parent_id ON categories(parent_id);

-- Insert sample categories
INSERT INTO categories (name, description, parent_id) VALUES
    ('Electronics', 'Electronic devices and accessories', NULL),
    ('Computers', 'Desktop and laptop computers', 1),
    ('Smartphones', 'Mobile phones and accessories', 1),
    ('Clothing', 'Apparel and fashion items', NULL),
    ('Men''s Clothing', 'Clothing for men', 4),
    ('Women''s Clothing', 'Clothing for women', 4),
    ('Books', 'Physical and digital books', NULL),
    ('Fiction', 'Fiction books', 7),
    ('Non-Fiction', 'Non-fiction books', 7)
ON CONFLICT (name) DO NOTHING;

-- Insert sample products
INSERT INTO products (sku, name, description, price, category, inventory_count, image_url) VALUES
    ('LAPTOP-001', 'Developer Laptop Pro', 'High-performance laptop for developers with 32GB RAM and 1TB SSD', 1499.99, 'Computers', 25, 'https://via.placeholder.com/300x300?text=Laptop'),
    ('LAPTOP-002', 'Business Ultrabook', 'Lightweight ultrabook perfect for business professionals', 1199.99, 'Computers', 30, 'https://via.placeholder.com/300x300?text=Ultrabook'),
    ('PHONE-001', 'Smartphone X', 'Latest flagship smartphone with advanced camera system', 999.99, 'Smartphones', 50, 'https://via.placeholder.com/300x300?text=Phone'),
    ('PHONE-002', 'Budget Smartphone', 'Affordable smartphone with great features', 299.99, 'Smartphones', 100, 'https://via.placeholder.com/300x300?text=Budget+Phone'),
    ('SHIRT-001', 'Classic T-Shirt', 'Comfortable cotton t-shirt in various colors', 29.99, 'Men''s Clothing', 200, 'https://via.placeholder.com/300x300?text=T-Shirt'),
    ('SHIRT-002', 'Dress Shirt', 'Professional dress shirt for business wear', 59.99, 'Men''s Clothing', 75, 'https://via.placeholder.com/300x300?text=Dress+Shirt'),
    ('DRESS-001', 'Summer Dress', 'Light and comfortable summer dress', 79.99, 'Women''s Clothing', 60, 'https://via.placeholder.com/300x300?text=Dress'),
    ('BOOK-001', 'The DevOps Handbook', 'Comprehensive guide to DevOps practices', 45.99, 'Non-Fiction', 40, 'https://via.placeholder.com/300x300?text=DevOps+Book'),
    ('BOOK-002', 'Kubernetes in Action', 'Learn Kubernetes from scratch', 55.99, 'Non-Fiction', 35, 'https://via.placeholder.com/300x300?text=K8s+Book'),
    ('BOOK-003', 'Science Fiction Adventure', 'Exciting sci-fi novel set in space', 24.99, 'Fiction', 80, 'https://via.placeholder.com/300x300?text=SciFi+Book')
ON CONFLICT (sku) DO NOTHING;

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
DROP TRIGGER IF EXISTS update_products_updated_at ON products;
CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create view for products with low inventory
CREATE OR REPLACE VIEW low_inventory_products AS
SELECT
    id,
    sku,
    name,
    price,
    category,
    inventory_count
FROM products
WHERE inventory_count < 10
ORDER BY inventory_count ASC;

-- Create view for product statistics by category
CREATE OR REPLACE VIEW category_statistics AS
SELECT
    category,
    COUNT(*) as product_count,
    SUM(inventory_count) as total_inventory,
    AVG(price) as average_price,
    MIN(price) as min_price,
    MAX(price) as max_price
FROM products
GROUP BY category
ORDER BY product_count DESC;

-- Grant permissions (for Vault-generated users)
-- Note: Vault will create users dynamically with appropriate permissions
-- These are example grants for reference

-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO "readonly_role";
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "readwrite_role";
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "readwrite_role";

-- Display initialization summary
DO $$
DECLARE
    product_count INTEGER;
    category_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO product_count FROM products;
    SELECT COUNT(*) INTO category_count FROM categories;

    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Products Database Initialization Complete';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Categories created: %', category_count;
    RAISE NOTICE 'Products created: %', product_count;
    RAISE NOTICE '===========================================';
END $$;
