from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, NoSuchElementException
import tempfile
import time
import os
import sys

def test_step(step_name, test_function):
    """Helper function to run individual test steps with error handling"""
    try:
        print(f"🧪 Testing: {step_name}")
        result = test_function()
        print(f"✅ PASS: {step_name}")
        return True, result
    except Exception as e:
        print(f"❌ FAIL: {step_name} - {str(e)}")
        return False, None

def wait_for_app_to_start(driver, max_attempts=30):
    """Wait for the Flask app to be accessible"""
    for attempt in range(max_attempts):
        try:
            driver.get("http://localhost:5000/")
            # Try to find any element on the page to confirm it loaded
            WebDriverWait(driver, 2).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )
            print("✅ Flask app is accessible")
            return True
        except:
            print(f"⏳ Waiting for Flask app... (attempt {attempt + 1}/{max_attempts})")
            time.sleep(2)
    return False

# Set up Chrome options for headless mode and performance
chrome_options = Options()
chrome_options.add_argument("--headless")
chrome_options.add_argument("--no-sandbox")
chrome_options.add_argument("--disable-dev-shm-usage")
chrome_options.add_argument("--disable-gpu")
chrome_options.add_argument("--window-size=1920,1080")

# Use a unique temporary user data directory
user_data_dir = tempfile.mkdtemp()
chrome_options.add_argument(f"--user-data-dir={user_data_dir}")

# Start the browser
driver = webdriver.Chrome(options=chrome_options)

# Track test results
test_results = []
overall_success = True

try:
    print("🚀 Starting Selenium tests for Chat App")
    print("=" * 50)
    
    # Test 1: Check if Flask app is accessible
    success, _ = test_step(
        "Flask app accessibility", 
        lambda: wait_for_app_to_start(driver)
    )
    test_results.append(("App Accessibility", success))
    
    if not success:
        print("❌ Cannot access Flask app. Skipping remaining tests.")
        overall_success = False
    else:
        # Test 2: Check if login page loads
        success, username_input = test_step(
            "Login page load and username input presence",
            lambda: WebDriverWait(driver, 10).until(
                EC.presence_of_element_located((By.ID, "username-input"))
            )
        )
        test_results.append(("Login Page Load", success))
        
        if success:
            # Test 3: Enter username
            success, _ = test_step(
                "Enter username",
                lambda: username_input.send_keys("seleniumuser") or True
            )
            test_results.append(("Username Entry", success))
            
            # Test 4: Click login button
            success, _ = test_step(
                "Click login button",
                lambda: WebDriverWait(driver, 10).until(
                    EC.element_to_be_clickable((By.ID, "login-button"))
                ).click() or True
            )
            test_results.append(("Login Button Click", success))
            
            if success:
                # Test 5: Wait for chat interface
                success, message_input = test_step(
                    "Chat interface loads",
                    lambda: WebDriverWait(driver, 10).until(
                        EC.presence_of_element_located((By.ID, "message-input"))
                    )
                )
                test_results.append(("Chat Interface Load", success))
                
                if success:
                    # Test 6: Send a message
                    test_message = "Hello from Selenium!"
                    success, _ = test_step(
                        "Send test message",
                        lambda: (
                            message_input.send_keys(test_message),
                            message_input.send_keys(Keys.RETURN)
                        )[-1] or True
                    )
                    test_results.append(("Send Message", success))
                    
                    if success:
                        # Test 7: Verify message appears
                        success, _ = test_step(
                            "Verify message appears in chat",
                            lambda: WebDriverWait(driver, 10).until(
                                lambda d: any(test_message in m.text for m in d.find_elements(By.CLASS_NAME, "message-text"))
                            ) or True
                        )
                        test_results.append(("Message Verification", success))

except KeyboardInterrupt:
    print("\n🛑 Test interrupted by user")
    overall_success = False
except Exception as e:
    print(f"🚨 Unexpected error: {str(e)}")
    overall_success = False

finally:
    driver.quit()
    # Clean up the temporary user data directory
    try:
        import shutil
        shutil.rmtree(user_data_dir)
    except Exception:
        pass

# Print test summary
print("\n" + "=" * 50)
print("📊 TEST SUMMARY")
print("=" * 50)

passed_tests = 0
total_tests = len(test_results)

for test_name, success in test_results:
    status = "✅ PASS" if success else "❌ FAIL"
    print(f"{status}: {test_name}")
    if success:
        passed_tests += 1
    else:
        overall_success = False

print(f"\n📈 Results: {passed_tests}/{total_tests} tests passed")

if overall_success and passed_tests == total_tests:
    print("🎉 All tests passed!")
    sys.exit(0)
else:
    print("⚠️  Some tests failed, but execution completed")
    # You can choose to exit with code 1 to fail CI, or 0 to pass with warnings
    sys.exit(1)  # Fail the CI build if any test fails