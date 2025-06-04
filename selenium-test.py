from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.chrome.options import Options
import tempfile
import time
import os

# Set up Chrome options for headless mode (optional)
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
    time.sleep(1)

    # Enter username and join chat
    username_input = driver.find_element(By.ID, "username-input")
    username_input.send_keys("seleniumuser")
    login_button = driver.find_element(By.ID, "login-button")
    login_button.click()
    time.sleep(2)  # Wait for chat to load

    # Send a message
    message_input = driver.find_element(By.ID, "message-input")
    test_message = "Hello from Selenium!"
    message_input.send_keys(test_message)
    message_input.send_keys(Keys.RETURN)
    time.sleep(1)

    # Check if the message appears in the chat
    messages = driver.find_elements(By.CLASS_NAME, "message-text")
    assert any(test_message in m.text for m in messages), "Test message not found in chat!"

    print("Selenium test passed: Message sent and found in chat.")

finally:
    driver.quit()
    # Clean up the temporary user data directory
    try:
        import shutil
        shutil.rmtree(user_data_dir)
    except Exception:
        pass
