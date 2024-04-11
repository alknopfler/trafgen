# Monitor softnet stats
# Author Mus
# mbayramov@vmware.com

def process_soft_net_stat(file_path):
    """
    Process and display softnet statistics from the given file.

    :param file_path: Path to the file containing softnet statistics.
    """
    stat_labels = [
        'sd->processed',
        'sd->dropped',
        'sd->time_squeeze',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        'sd->received_rps',
        'flow_limit_count',
        'softnet_backlog_len(sd)',
        '(int)seq->index)'
    ]

    with open(file_path) as file:
        for cpu_index, line in enumerate(file):
            print(f"CPU {cpu_index}")
            stats = line.split()

            max_len = max(len(label) for label in stat_labels) + 5
            for label, stat in zip(stat_labels, stats):
                stat_int = int(stat, 16)
                print(f"{label.ljust(max_len)} {stat_int}")

            print("")

if __name__ == "__main__":
    file_path = '/proc/net/softnet_stat'
    process_soft_net_stat(file_path)
