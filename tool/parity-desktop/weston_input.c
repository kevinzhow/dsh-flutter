/* Test-only synthetic input for Weston 14's private headless compositor.
 * Commands arrive on an inherited pipe, never a host input device or socket.
 * The seat/notify functions are Weston 14 private ABI, matching backend.h and
 * libweston-internal.h in https://gitlab.freedesktop.org/wayland/weston/-/tree/14.0.2
 * Build against the same libweston-14 headers as the installed compositor.
 */
#include <errno.h>
#include <fcntl.h>
#include <libweston/libweston.h>
#include <libweston/version.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if WESTON_VERSION_MAJOR != 14
#error This test module requires Weston 14
#endif

void weston_seat_init(struct weston_seat *, struct weston_compositor *, const char *);
void weston_seat_release(struct weston_seat *);
int weston_seat_init_pointer(struct weston_seat *);
int weston_seat_init_keyboard(struct weston_seat *, struct xkb_keymap *);
void notify_motion_absolute(struct weston_seat *, const struct timespec *, struct weston_coord_global);
void notify_button(struct weston_seat *, const struct timespec *, int32_t, enum wl_pointer_button_state);
void notify_key(struct weston_seat *, const struct timespec *, uint32_t,
                enum wl_keyboard_key_state, enum weston_key_state_update);
void notify_axis(struct weston_seat *, const struct timespec *, struct weston_pointer_axis_event *);
void notify_pointer_frame(struct weston_seat *);

struct input {
    struct weston_seat seat;
    struct wl_event_source *source;
    struct wl_listener destroy;
    int fd;
    char line[128];
    size_t used;
};

static int command(struct input *in)
{
    struct timespec now;
    double x, y;
    unsigned code, state;
    char extra;
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (sscanf(in->line, "move %lf %lf %c", &x, &y, &extra) == 2) {
        struct weston_coord_global pos = { .c = { .x = x, .y = y } };
        notify_motion_absolute(&in->seat, &now, pos);
    } else if (sscanf(in->line, "button %u %u %c", &code, &state, &extra) == 2 && state <= 1) {
        notify_button(&in->seat, &now, code, state);
    } else if (sscanf(in->line, "key %u %u %c", &code, &state, &extra) == 2 && state <= 1) {
        notify_key(&in->seat, &now, code, state, STATE_UPDATE_AUTOMATIC);
    } else if (sscanf(in->line, "scroll %lf %c", &y, &extra) == 1) {
        struct weston_pointer_axis_event axis = {
            .axis = WL_POINTER_AXIS_VERTICAL_SCROLL, .value = y,
        };
        notify_axis(&in->seat, &now, &axis);
    } else {
        return -1;
    }
    notify_pointer_frame(&in->seat);
    return 0;
}

static int receive(int fd, uint32_t mask, void *data)
{
    struct input *in = data;
    char buf[256];
    ssize_t n;
    (void)mask;
    while ((n = read(fd, buf, sizeof buf)) > 0) {
        for (ssize_t i = 0; i < n; i++) {
            if (buf[i] == '\n') {
                in->line[in->used] = '\0';
                if (command(in) < 0)
                    goto invalid;
                in->used = 0;
            } else if (in->used + 1 < sizeof in->line) {
                in->line[in->used++] = buf[i];
            } else {
                goto invalid;
            }
        }
    }
    if (n == 0 || (errno != EAGAIN && errno != EINTR))
        wl_display_terminate(in->seat.compositor->wl_display);
    return 0;
invalid:
    fprintf(stderr, "Whalee test input: invalid command; terminating test compositor\n");
    wl_display_terminate(in->seat.compositor->wl_display);
    return 0;
}

static void destroy(struct wl_listener *listener, void *data)
{
    struct input *in = wl_container_of(listener, in, destroy);
    (void)data;
    wl_event_source_remove(in->source);
    weston_seat_release(&in->seat);
    close(in->fd);
    wl_list_remove(&in->destroy.link);
    free(in);
}

WL_EXPORT int wet_module_init(struct weston_compositor *compositor, int *argc, char *argv[])
{
    const char *value = getenv("WHALEE_TEST_INPUT_FD");
    char *end;
    struct input *in;
    long fd;
    (void)argc;
    (void)argv;
    if (!value || !*value)
        return -1;
    fd = strtol(value, &end, 10);
    if (*end || fd < 3 || fd > 1024 || fcntl(fd, F_GETFD) < 0)
        return -1;
    in = calloc(1, sizeof *in);
    if (!in)
        return -1;
    in->fd = fd;
    fcntl(in->fd, F_SETFL, O_NONBLOCK);
    weston_seat_init(&in->seat, compositor, "whalee-test-seat");
    if (weston_seat_init_pointer(&in->seat) < 0 || weston_seat_init_keyboard(&in->seat, NULL) < 0)
        goto fail;
    in->source = wl_event_loop_add_fd(wl_display_get_event_loop(compositor->wl_display),
                                      in->fd, WL_EVENT_READABLE, receive, in);
    if (!in->source)
        goto fail;
    in->destroy.notify = destroy;
    wl_signal_add(&compositor->destroy_signal, &in->destroy);
    return 0;
fail:
    weston_seat_release(&in->seat);
    free(in);
    return -1;
}
