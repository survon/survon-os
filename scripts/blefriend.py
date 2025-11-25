#!/usr/bin/env python3
"""
Simple script to communicate with Adafruit Bluefruit LE Friend
"""

import serial
import time

# Configuration
PORT = '/dev/cu.usbserial-0143857C'
BAUD_RATE = 9600

def test_connection(ser):
  """Test basic AT command"""
  print("\nTesting connection with 'AT' command...")
  ser.write(b'AT\r\n')
  time.sleep(0.5)
  
  if ser.in_waiting:
    response = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
    print(f"Response: {response}")
    return True
  else:
    print("No response received")
    return False

def get_firmware_info(ser):
  """Get firmware information with ATI command"""
  print("\nGetting firmware info with 'ATI' command...")
  ser.write(b'ATI\r\n')
  time.sleep(0.5)
  
  if ser.in_waiting:
    response = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
    print(f"Firmware Info:\n{response}")
  else:
    print("No response received")

def main():
  print(f"Connecting to Bluefruit LE Friend on {PORT} at {BAUD_RATE} baud...")
  
  try:
    # Open serial connection with hardware flow control
    ser = serial.Serial(
      port=PORT,
      baudrate=BAUD_RATE,
      bytesize=serial.EIGHTBITS,
      parity=serial.PARITY_NONE,
      stopbits=serial.STOPBITS_ONE,
      timeout=1,
      rtscts=True  # Hardware flow control
    )
    
    print("Connected!")
    time.sleep(2)  # Give device time to settle
    
    # Clear any existing data
    if ser.in_waiting:
      ser.read(ser.in_waiting)
    
    # Test basic communication
    if test_connection(ser):
      # If AT works, try getting firmware info
      get_firmware_info(ser)
    
    ser.close()
    print("\nDone!")
  
  except serial.SerialException as e:
    print(f"Error: {e}")
    print("\nMake sure:")
    print("1. The dongle is plugged in")
    print("2. No other programs are using the serial port")
    print("3. The MODE switch is set to CMD")

if __name__ == "__main__":
  main()
