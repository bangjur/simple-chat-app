from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import tempfile
import time
import sys

def wait_for_flask_app(driver, url="http://localhost:5000/", timeout=30):
    for i in range(timeout):
        try:
            driver.get(url)
            WebDriverWait(driver, 2).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )
            print(f"✅ Flask app is accessible at {url}")
            return True
        except Exception:
            print(f"⏳ Waiting for Flask app... ({i+1}/{timeout})")
            time.sleep(1)
    print("❌ Flask app not accessible after waiting.")
    return False

def run_step(step_name, func):
    try:
        print(f"🧪 {step_name} ... ", end="")
        result = func()
        print("✅")
        return True, result
    except Exception as e:
        print(f"❌ ({e})")
        return False, None

chrome_options = Options()
chrome_options.add_argument("--headless")
chrome_options.add_argument("--no-sandbox")
chrome_options.add_argument("--disable-dev-shm-usage")
user_data_dir = tempfile.mkdtemp()
chrome_options.add_argument(f"--user-data-dir={user_data_dir}")

driver = webdriver.Chrome(options=chrome_options)
results = []

try:
    # 1. Wait for Flask app
    results.append(run_step("Wait for Flask app", lambda: wait_for_flask_app(driver)))

    # 2. Check username input
    results.append(run_step("Check username input", lambda: WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "username-input"))
    )))

    # 3. Enter username
    def enter_username():
        username_input = driver.find_element(By.ID, "username-input")
        username_input.clear()
        username_input.send_keys("seleniumuser")
    results.append(run_step("Enter username", enter_username))

    # 4. Check login button
    results.append(run_step("Check login button", lambda: WebDriverWait(driver, 10).until(
        EC.element_to_be_clickable((By.ID, "login-button"))
    )))

    # 5. Click login button
    def click_login():
        login_button = driver.find_element(By.ID, "login-button")
        login_button.click()
    results.append(run_step("Click login button", click_login))

    # 6. Wait for message input
    results.append(run_step("Wait for message input", lambda: WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "message-input"))
    )))

    # 7. Send a message
    def send_message():
        message_input = driver.find_element(By.ID, "message-input")
        test_message = "Hello from Selenium!"
        message_input.send_keys(test_message)
        message_input.send_keys(Keys.RETURN)
        return test_message
    msg_success, test_message = run_step("Send a message", send_message)
    results.append((msg_success, test_message))

    # 8. Check if message appears
    def check_message():
        WebDriverWait(driver, 10).until(
            lambda d: any(test_message in m.text for m in d.find_elements(By.CLASS_NAME, "message-text"))
        )
    results.append(run_step("Check if message appears", check_message))

finally:
    driver.quit()
    try:
        import shutil
        shutil.rmtree(user_data_dir)
    except Exception:
        pass

# Print summary
print("\n=== TEST SUMMARY ===")
passed = 0
for idx, (success, _) in enumerate(results, 1):
    print(f"Step {idx}: {'✅ PASS' if success else '❌ FAIL'}")
    if success:
        passed += 1
print(f"\n{passed}/{len(results)} steps passed.")
if passed == len(results):
    sys.exit(0)
else:
    sys.exit(1)
