pad_size = 20

stat_map = {
    0: 'sd->processed',
    1: 'sd->dropped',
    2: 'sd->time_squeeze',
    3: '0',
    4: '0',
    5: '0',
    6: '0',
    7: '0',
    8: '0',
    9: 'sd->received_rps',
    10: 'flow_limit_count',
    11: 'softnet_backlog_len(sd)',
    12: '(int)seq->index)'
}


def calculate_justify_len(value):
    return max(len(str(value)), pad_size)

with open('/proc/net/softnet_stat') as f:
    i = 0
    for cpu in f:
        print(f"CPU {i}")
        stats = cpu.split(' ')

        if len(stats) != len(stat_map):
            print("Error: Number of columns in stats does not match the expected length based on map.")
            continue

        for j, stat in enumerate(stats):
            justify_by = calculate_justify_len(stat)
            print(stat_map[j].ljust(justify_by), end=' ')

        print("\n")
        i += 1
