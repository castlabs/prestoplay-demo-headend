#!/usr/bin/env python3
import os
import subprocess
import signal
import sys
import argparse
from shutil import rmtree

location = os.path.dirname(os.path.realpath(__file__))
processes = []
ipAddress = '233.1.1.5'
iptv_script = "{}/source-stream/source-stream.sh".format(location)
dash_script = "{}/dash-stream/dash-stream.sh".format(location)


def cleanup():
    print("Cleaning live data folder")
    # rmtree('/Users/castlabdemos/demos/webserver/root/live')


def signal_handler(signum, frame):
    print('Signal handler called with signal', signum)
    for process in processes:
        process.kill()
    cleanup()
    sys.exit(1)


os.environ["PATH"] += os.pathsep + '/opt/homebrew/bin'

# Set the signal handler and a 5-second alarm
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


def run(inputs, webserver):
    print("Base dir: {}".format(location))
    print("Inputs: {}".format(inputs))

    start_port = 1234

    for counter, source in enumerate(inputs):
        port = start_port + counter
        print("Start {}:{} for {}".format(ipAddress, port, source))
        p = subprocess.Popen([iptv_script, '--bitrate', '8M',
                              '-i', source,
                              '--ip', ipAddress,
                              '-p', "{}".format(port)],
                             stderr=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL)
        processes.append(p)

    for counter, source in enumerate(inputs):
        port = start_port + counter
        web_target = "{}/live/live-{}/manifest.mpd".format(webserver, counter)
        print("Start DASH for {}:{} and ingest to {}".format(
            ipAddress, port, web_target))

        p = subprocess.Popen([dash_script,
                              '-i', "{}:{}".format(ipAddress, port),
                              '--renditions', "1080:8M:high,540:2M:high",
                              '--fragment-duration', "0.1",
                              '--time-server', "{}/time".format(webserver),
                              '--origin', web_target],
                             stderr=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL)
        processes.append(p)
    #
    for process in processes:
        process.wait()
    print("All done, cleaning up")
    cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Start IP-TV and DASH streams')
    parser.add_argument('inputs', metavar='source', type=str, nargs='+',
                        help='The input sources')
    parser.add_argument("--webserver", metavar='webserver', type=str,
                        default='https://tradeshows.castlabs.com',
                        help='URL to the webserver that will be used for '
                             'ingest. Defaults to '
                             'https://tradeshows.castlabs.com')

    args = parser.parse_args()

    run(args.inputs, args.webserver)
