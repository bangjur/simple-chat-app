from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import tempfile
import time
import os

# Set up Chrome options for headless mode and performance
chrome_options = Options()
chrome_options.add_argument("--headless")
chrome_options.add_argument("--no-sandbox")
chrome_options.add_argument("--disable-dev-shm-usage")

# Use a unique temporary user data directory
user_data_dir = tempfile.mkdtemp()
chrome_options.add_argument(f"--user-data-dir={user_data_dir}")

# Start the browser
driver = webdriver.Chrome(options=chrome_options)

try:
    # Open the chat app
    driver.get("http://localhost:5000/")
    
    # Wait for username input to be present and send username
    username_input = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "username-input"))
    )
    username_input.send_keys("seleniumuser")
    
    # Wait for login button to be clickable and click it
    login_button = WebDriverWait(driver, 10).until(
        EC.element_to_be_clickable((By.ID, "login-button"))
    )
    login_button.click()
    
    # Wait for the message input to appear in the chat screen
    message_input = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "message-input"))
    )
    
    # Send a message
    test_message = "Hello from Selenium!"
    message_input.send_keys(test_message)
    message_input.send_keys(Keys.RETURN)
    
    # Wait until the sent message appears in the chat
    WebDriverWait(driver, 10).until(
        lambda d: any(test_message in m.text for m in d.find_elements(By.CLASS_NAME, "message-text"))
    )
    
    print("Selenium test passed: Message sent and found in chat.")

finally:
    driver.quit()
    # Clean up the temporary user data directory
    try:
        import shutil
        shutil.rmtree(user_data_dir)
    except Exception:
        pass
